# frozen_string_literal: true

module Enrichment
  # One phase: artist.getTopTags identifies and answers in the same request, so there
  # is nothing to match first.
  class LastfmStrategy
    SOURCE = :lastfm
    # Last.fm publishes no hard limit, only that sustained "several calls per second"
    # gets an account suspended. Four per second stays well under that.
    MIN_INTERVAL = 0.25
    BATCH_SIZE = 120

    def initialize(adapter: LastfmAdapter.new)
      @adapter = adapter
      @applier = GenreApplier.new(source: SOURCE)
      @mbids = {}
    end

    def source = SOURCE
    def min_interval = MIN_INTERVAL
    def batch_size = BATCH_SIZE
    def match_batch_size = 1

    def needs_match?(_row) = false

    def match(_rows) = { matched: 0, unmatched: 0 }

    # MusicBrainz's exact Spotify link makes Last.fm's lookup exact too, so borrow the
    # MBID whenever the sibling row has one. Loaded in one query per tick rather than
    # one per row.
    def prepare(rows)
      @mbids = ArtistMetadataSource
               .where(source: :musicbrainz, state: :matched, artist_id: rows.map(&:artist_id))
               .where.not(external_id: nil)
               .pluck(:artist_id, :external_id)
               .to_h
    end

    def fetch(row)
      result = adapter.artist_top_tags(name: row.artist.name, mbid: mbids[row.artist_id])
      applier.call(row.artist_id, result.genres)
      row.record_fetch!(external_id: result.name, external_url: result.url)
      :fetched
    rescue Lastfm::NotFoundError
      row.record_unmatched!
      :unmatched
    end

    private

    attr_reader :adapter, :applier, :mbids
  end
end
