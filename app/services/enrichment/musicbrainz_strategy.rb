# frozen_string_literal: true

module Enrichment
  # Two phases, because MusicBrainz needs an MBID before it will talk about genres.
  # Matching is batched (25 Spotify URLs in one request) so it is nearly free; the
  # genre fetch is one request per artist and is what the pace actually costs.
  #
  # A newly matched row is left for the next tick rather than fetched immediately,
  # which keeps every tick the same shape and the budget honest.
  class MusicbrainzStrategy
    SOURCE = :musicbrainz
    MIN_INTERVAL = 1.0
    BATCH_SIZE = 60

    def initialize(adapter: MusicbrainzAdapter.new)
      @adapter = adapter
      @applier = GenreApplier.new(source: SOURCE)
    end

    def source = SOURCE
    def min_interval = MIN_INTERVAL
    def batch_size = BATCH_SIZE
    def match_batch_size = MusicbrainzAdapter::RESOURCE_BATCH_LIMIT

    def needs_match?(row) = row.external_id.blank?

    def prepare(_rows) = nil

    def match(rows)
      rows_by_spotify_id = rows.index_by { |row| row.artist.spotify_id }
      mbids = adapter.artists_by_spotify_url(rows_by_spotify_id.keys)

      rows_by_spotify_id.each_with_object({ matched: 0, unmatched: 0 }) do |(spotify_id, row), counts|
        mbid = mbids[spotify_id]
        mbid.present? ? row.record_match!(external_id: mbid) : row.record_unmatched!
        counts[mbid.present? ? :matched : :unmatched] += 1
      end
    end

    def fetch(row)
      applier.call(row.artist_id, adapter.artist_genres(row.external_id))
      row.record_fetch!
      :fetched
    rescue Musicbrainz::NotFoundError
      # The MBID we stored no longer resolves. record_unmatched! clears it, so the
      # next pass re-matches from the Spotify link instead of retrying a dead id.
      row.record_unmatched!
      :unmatched
    end

    private

    attr_reader :adapter, :applier
  end
end
