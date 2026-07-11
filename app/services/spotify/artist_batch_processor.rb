# frozen_string_literal: true

module Spotify
  class ArtistBatchProcessor
    Result = Struct.new(:session_completed?, :skipped?, keyword_init: true)

    attr_reader :session, :artist_ids, :adapter

    def initialize(session, artist_ids:, adapter:)
      @session = session
      @artist_ids = artist_ids
      @adapter = adapter
    end

    def call
      return Result.new(skipped?: true) if session.failed?

      spotify_ids = Artist.where(id: artist_ids).pluck(:spotify_id)
      return Result.new(skipped?: true) if spotify_ids.empty?

      fetch_and_upsert_artists(spotify_ids)
      session_completed = complete_batch!

      Result.new(session_completed?: session_completed, skipped?: false)
    end

    private

    def fetch_and_upsert_artists(spotify_ids)
      response = adapter.artists(spotify_ids)
      Spotify::ArtistMetadataUpserter.new(response).call
    end

    def complete_batch!
      session_completed = session.batch_completed!
      session.update!(status: :completed, completed_at: Time.current) if session_completed
      session_completed
    end
  end
end
