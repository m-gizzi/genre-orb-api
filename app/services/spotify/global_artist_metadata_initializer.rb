# frozen_string_literal: true

module Spotify
  class GlobalArtistMetadataInitializer
    include SessionClaim

    BATCH_SIZE = SpotifyAdapter::ARTIST_BATCH_LIMIT

    MAX_BATCHES_PER_RUN = 2_000

    Result = Struct.new(:outcome, :session, :batches, keyword_init: true) { include StartableResult }

    def initialize(scheduled_run: nil)
      @scheduled_run = scheduled_run
    end

    def call
      return Result.new(outcome: :already_in_progress) if ArtistMetadataSession.global.active.exists?
      return Result.new(outcome: :no_artists) if batches.empty?

      start_sync
    end

    private

    attr_reader :scheduled_run

    def start_sync
      session = create_session
      return Result.new(outcome: :already_in_progress) unless session

      enqueue_batch_jobs(session)
      Result.new(outcome: :started, session: session, batches: batches)
    end

    def batches
      @batches ||= artist_ids.each_slice(BATCH_SIZE).to_a
    end

    def artist_ids
      Artist.needs_metadata.limit(BATCH_SIZE * MAX_BATCHES_PER_RUN).pluck(:id)
    end

    def create_session
      claim do
        ArtistMetadataSession.create!(
          user: nil,
          scheduled_run: scheduled_run,
          status: :running,
          total_batches: batches.size,
          completed_batches: 0,
          started_at: Time.current,
        )
      end
    end

    def enqueue_batch_jobs(session)
      jobs = batches.map { |batch_ids| ArtistBatchFetchJob.new(session_id: session.id, artist_ids: batch_ids) }
      ActiveJob.perform_all_later(jobs)
    end
  end
end
