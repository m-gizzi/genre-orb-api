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

      response = adapter.artists(spotify_ids)
      Spotify::ArtistMetadataUpserter.new(response).call

      session_completed = session.batch_completed!
      session.update!(status: :completed, completed_at: Time.current) if session_completed

      Result.new(session_completed?: session_completed, skipped?: false)
    end
  end
end
