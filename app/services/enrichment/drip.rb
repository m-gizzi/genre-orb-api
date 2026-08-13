# frozen_string_literal: true

module Enrichment
  # One tick of the continuous enrichment drip: top up the work table, take the stalest
  # due rows, and spend the tick's wall-clock budget on paced provider requests.
  #
  # Deliberately not a ScheduledRun stage. MusicBrainz allows one request per second,
  # so a first pass over a five-figure artist set is hours of wall clock — it would
  # blow the run's 6h hard cap and delay the push stage every night. Genres land when
  # they land and the nightly pushes pick up whatever is there.
  class Drip
    BACKFILL_LIMIT = 500
    DEFAULT_BUDGET = 20.seconds

    # Throttling stops the whole tick. Marking rows failed for it would burn their
    # failure_count and push innocent artists into an hours-long backoff.
    ABORT_ERRORS = [Musicbrainz::RateLimitError, Lastfm::RateLimitError].freeze
    EXPECTED_ERRORS = [Musicbrainz::NotFoundError, Lastfm::NotFoundError].freeze
    FAILURE_ERRORS = [Musicbrainz::ApiError, Lastfm::ApiError, Faraday::Error].freeze

    Result = Struct.new(:matched, :fetched, :unmatched, :failed, :aborted, keyword_init: true) do
      def to_s
        "matched=#{matched} fetched=#{fetched} unmatched=#{unmatched} failed=#{failed} aborted=#{aborted}"
      end
    end

    # The strategy decides the pace, so this is the constructor callers want; specs
    # build one directly with a zero-interval pacer.
    def self.for(strategy, deadline: DEFAULT_BUDGET.from_now)
      new(strategy: strategy, deadline: deadline, pacer: Pacer.new(strategy.min_interval))
    end

    def initialize(strategy:, deadline:, pacer:)
      @strategy = strategy
      @deadline = deadline
      @pacer = pacer
      @tally = { matched: 0, fetched: 0, unmatched: 0, failed: 0 }
    end

    def call
      backfill
      aborted = run_phases
      Result.new(**tally, aborted: aborted)
    end

    private

    attr_reader :strategy, :deadline, :pacer, :tally

    def run_phases
      rows = due_rows
      return false if rows.empty?

      strategy.prepare(rows)
      to_match, to_fetch = rows.partition { |row| strategy.needs_match?(row) }
      match_phase(to_match)
      fetch_phase(to_fetch)
      false
    rescue *ABORT_ERRORS => e
      Rails.logger.info("Enrichment drip (#{strategy.source}) stopped early: #{e.message}")
      true
    end

    # Rows with no row for this source yet. Creating them up front is what lets the
    # work query be one indexed scan over artist_metadata_sources alone.
    def backfill
      rows = missing_artist_ids.map { |artist_id| pending_row_for(artist_id) }
      return if rows.empty?

      ArtistMetadataSource.insert_all(rows, unique_by: %i[artist_id source])
    end

    def missing_artist_ids
      Artist
        .where.not(id: ArtistMetadataSource.where(source: strategy.source).select(:artist_id))
        .order(:id)
        .limit(BACKFILL_LIMIT)
        .pluck(:id)
    end

    def pending_row_for(artist_id)
      {
        artist_id: artist_id,
        source: ArtistMetadataSource.sources.fetch(strategy.source.to_s),
        state: ArtistMetadataSource.states.fetch("pending"),
        created_at: Time.current,
        updated_at: Time.current,
      }
    end

    def due_rows
      ArtistMetadataSource
        .where(source: strategy.source)
        .due
        .stalest_first
        .limit(strategy.batch_size)
        .includes(:artist)
        .to_a
    end

    def match_phase(rows)
      rows.each_slice(strategy.match_batch_size) do |batch|
        break if past_deadline?

        match_batch(batch)
      end
    end

    def match_batch(batch)
      pacer.wait
      attempt(batch) { record_counts(strategy.match(batch)) }
    end

    def record_counts(counts)
      counts.each { |outcome, count| tally[outcome] += count }
    end

    def fetch_phase(rows)
      rows.each do |row|
        break if past_deadline?

        pacer.wait
        attempt([row]) { tally[strategy.fetch(row)] += 1 }
      end
    end

    # Rescue order matters: RateLimitError and NotFoundError both descend from
    # ApiError, so the specific clauses have to come first.
    def attempt(rows)
      yield
    rescue *ABORT_ERRORS
      raise
    rescue *EXPECTED_ERRORS
      mark_unmatched(rows)
    rescue *FAILURE_ERRORS => e
      mark_failed(rows, e)
    end

    def mark_unmatched(rows)
      rows.each(&:record_unmatched!)
      tally[:unmatched] += rows.size
    end

    def mark_failed(rows, error)
      Rails.logger.warn(
        "Enrichment drip (#{strategy.source}) failed for artists #{rows.map(&:artist_id)}: #{error.message}",
      )
      rows.each { |row| row.record_failure!(error) }
      tally[:failed] += rows.size
    end

    def past_deadline? = Time.current >= deadline
  end
end
