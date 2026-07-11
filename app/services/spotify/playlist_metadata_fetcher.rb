# frozen_string_literal: true

module Spotify
  class PlaylistMetadataFetcher
    SPOTIFY_PAGE_SIZE = 50

    Result = Struct.new(:success?, :playlists, :error, keyword_init: true)

    attr_reader :user, :adapter

    def initialize(user)
      @user = user
      @adapter = SpotifyAdapter.new(user.spotify_connection)
    end

    def call
      spotify_playlists = fetch_all_playlists
      sync_playlists(spotify_playlists)

      Result.new(success?: true, playlists: user.playlists)
    rescue SpotifyAdapter::RateLimitError
      raise
    rescue StandardError => e
      Rails.logger.error("PlaylistMetadataFetcher error for user #{user.id}: #{e.message}")
      user.update!(playlists_metadata_error: e.message)
      Result.new(success?: false, error: e.message)
    end

    private

    def sync_playlists(spotify_playlists)
      liked_accessible = liked_songs_accessible?

      ActiveRecord::Base.transaction do
        upsert_playlists(spotify_playlists)
        upsert_liked_songs if liked_accessible
        mark_unavailable_playlists(spotify_playlists.map { |playlist| playlist["id"] })
        user.update!(playlists_metadata_fetched_at: Time.current, playlists_metadata_error: nil)
      end
    end

    def fetch_all_playlists
      playlists = []
      offset = 0

      loop do
        response = adapter.playlists(limit: SPOTIFY_PAGE_SIZE, offset: offset)
        playlists.concat(response["items"] || [])
        break unless response["next"]

        offset += SPOTIFY_PAGE_SIZE
      end

      playlists
    end

    def liked_songs_accessible?
      adapter.liked_songs(limit: 1).present?
    rescue SpotifyAdapter::RateLimitError
      raise
    rescue SpotifyAdapter::ApiError
      false
    end

    def upsert_playlists(spotify_playlists)
      return if spotify_playlists.empty?

      records = spotify_playlists.map { |sp| build_playlist_record(sp) }
      Playlist.upsert_all(
        records,
        unique_by: %i[user_id spotify_id],
        update_only: %i[name last_seen_snapshot_id is_public available_on_spotify],
      )
    end

    def build_playlist_record(spotify_playlist)
      {
        user_id: user.id,
        spotify_id: spotify_playlist["id"],
        name: spotify_playlist["name"],
        last_seen_snapshot_id: spotify_playlist["snapshot_id"],
        is_public: spotify_playlist["public"] || false,
        available_on_spotify: true,
        created_at: Time.current,
        updated_at: Time.current,
      }
    end

    def upsert_liked_songs
      liked = LikedSongsPlaylist.find_or_initialize_by(user: user)
      liked.name = "Liked Songs"
      liked.available_on_spotify = true
      liked.save!
    end

    def mark_unavailable_playlists(spotify_ids)
      user.playlists
          .regular
          .available
          .where.not(spotify_id: spotify_ids)
          .update_all(available_on_spotify: false, updated_at: Time.current)
    end
  end
end
