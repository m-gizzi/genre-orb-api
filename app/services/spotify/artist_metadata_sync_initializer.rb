# frozen_string_literal: true

module Spotify
  class ArtistMetadataSyncInitializer
    BATCH_SIZE = SpotifyAdapter::ARTIST_BATCH_LIMIT

    Result = Struct.new(:success?, :session, :batches, :skipped_reason, keyword_init: true)

    def initialize(user, sync_all: false)
      @user = user
      @sync_all = sync_all
    end

    def call
      artist_ids = fetch_artist_ids

      if artist_ids.empty?
        return Result.new(success?: true, skipped_reason: "no artists to sync")
      end

      batches = artist_ids.each_slice(BATCH_SIZE).to_a
      total_batches = batches.size

      session = ArtistMetadataSession.create!(
        user: @user,
        status: :running,
        total_batches: total_batches,
        completed_batches: 0,
        started_at: Time.current
      )

      Result.new(
        success?: true,
        session: session,
        batches: batches
      )
    end

    private

    def fetch_artist_ids
      if @sync_all
        Artist.pluck(:id)
      else
        Artist.where(metadata_fetched_at: nil).pluck(:id)
      end
    end
  end
end
