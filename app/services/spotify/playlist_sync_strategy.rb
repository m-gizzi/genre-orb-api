# frozen_string_literal: true

module Spotify
  class PlaylistSyncStrategy
    REGULAR_PAGE_SIZE = 100
    LIKED_SONGS_PAGE_SIZE = 50

    def initialize(playlist)
      @playlist = playlist
    end

    def page_size
      @playlist.liked_songs? ? LIKED_SONGS_PAGE_SIZE : REGULAR_PAGE_SIZE
    end

    def snapshot_unchanged?(current_api_snapshot_id)
      return false if @playlist.liked_songs?
      return false if @playlist.last_synced_snapshot_id.nil?

      @playlist.last_synced_snapshot_id == current_api_snapshot_id
    end

    def fetch_tracks_page(adapter, limit:, offset:)
      if @playlist.liked_songs?
        adapter.liked_songs(limit: limit.clamp(1, page_size), offset: offset)
      else
        adapter.playlist_tracks(@playlist.spotify_id, limit: limit, offset: offset)
      end
    end
  end
end
