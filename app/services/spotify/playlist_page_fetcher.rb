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
      items = fetch_page_items

      final_page = false
      ActiveRecord::Base.transaction do
        process_items(items)
        final_page = playlist_session.page_completed!
      end

      PlaylistSyncFinalizer.new(playlist_session).complete! if final_page
      Result.new(sync_completed?: final_page)
    end

    private

    def fetch_page_items
      page_size = strategy.page_size
      offset = page * page_size
      response = strategy.fetch_tracks_page(adapter, limit: page_size, offset: offset)
      response["items"] || []
    end

    def process_items(items)
      tracks_by_spotify_id = Spotify::TrackUpserter.new.call(items)
      offset = page * strategy.page_size
      Spotify::PlaylistVersionTrackBuilder.new(version).call(items, tracks_by_spotify_id, offset: offset)
    end

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
