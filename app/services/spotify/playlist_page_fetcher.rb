# frozen_string_literal: true

module Spotify
  class PlaylistPageFetcher
    Result = Struct.new(:sync_completed?, keyword_init: true)

    attr_reader :playlist_session, :page, :adapter

    def initialize(playlist_session, page:, adapter:)
      @playlist_session = playlist_session
      @page = page
      @adapter = adapter
    end

    def call
      page_size = strategy.page_size
      offset = page * page_size

      response = strategy.fetch_tracks_page(adapter, limit: page_size, offset: offset)
      items = response["items"] || []

      sync_completed = false

      ActiveRecord::Base.transaction do
        tracks_by_spotify_id = Spotify::TrackUpserter.new.call(items)
        Spotify::PlaylistVersionTrackBuilder.new(version).call(items, tracks_by_spotify_id, offset: offset)

        if playlist_session.page_completed!
          PlaylistSyncFinalizer.new(playlist_session).complete!
          sync_completed = true
        end
      end

      Result.new(sync_completed?: sync_completed)
    end

    private

    def playlist
      playlist_session.playlist
    end

    def version
      playlist_session.playlist_version
    end

    def strategy
      @strategy ||= PlaylistSyncStrategy.new(playlist)
    end
  end
end
