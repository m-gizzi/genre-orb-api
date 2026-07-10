# frozen_string_literal: true

module Spotify
  class ArtistMetadataSyncInitializer
    BATCH_SIZE = SpotifyAdapter::ARTIST_BATCH_LIMIT

    Result = Struct.new(:session, :batches, :skipped_reason, keyword_init: true)

    def initialize(user, sync_all: false)
      @user = user
      @sync_all = sync_all
    end

    def call
      artist_ids = fetch_artist_ids
      return Result.new(skipped_reason: "no artists to sync") if artist_ids.empty?

      batches = artist_ids.each_slice(BATCH_SIZE).to_a
      session = create_session(batches.size)

      Result.new(session: session, batches: batches)
    end

    private

    def fetch_artist_ids
      @sync_all ? Artist.pluck(:id) : Artist.where(metadata_fetched_at: nil).pluck(:id)
    end

    def create_session(total_batches)
      ArtistMetadataSession.create!(
        user: @user,
        status: :running,
        total_batches: total_batches,
        completed_batches: 0,
        started_at: Time.current,
      )
    end
  end
end
