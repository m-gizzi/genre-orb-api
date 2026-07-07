# frozen_string_literal: true

module Spotify
  class PlaylistPageFetcher
    Result = Struct.new(:success?, :sync_completed?, :error, keyword_init: true)

    def initialize(playlist_session, page:, adapter:)
      @playlist_session = playlist_session
      @playlist = playlist_session.playlist
      @version = playlist_session.playlist_version
      @page = page
      @adapter = adapter
    end

    def call
      page_size = @playlist.spotify_page_size
      offset = @page * page_size

      response = @playlist.fetch_tracks_page(@adapter, limit: page_size, offset: offset)
      items = response["items"] || []

      sync_completed = false

      ActiveRecord::Base.transaction do
        tracks_by_spotify_id = Spotify::TrackUpserter.new.call(items)
        Spotify::PlaylistVersionTrackBuilder.new(@version).call(items, tracks_by_spotify_id, offset: offset)

        if @playlist_session.page_completed!
          PlaylistSyncCompleter.new(@playlist_session).complete
          sync_completed = true
        end
      end

      Result.new(success?: true, sync_completed?: sync_completed)
    end
  end
end
