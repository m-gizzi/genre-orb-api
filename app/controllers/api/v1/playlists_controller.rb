# frozen_string_literal: true

module Api
  module V1
    class PlaylistsController < BaseController
      include SpotifyErrorRendering
      include GenreLoading

      def index
        scope = Playlists::Filter.new(current_user, params).call

        pagy, playlists = paginate(scope)
        render_data(PlaylistSerializer.new(playlists).serializable_hash, meta: pagy_meta(pagy))
      end

      def show
        playlist = current_user.playlists
                               .includes(:current_version, :smart_playlist_as_target)
                               .find(params.expect(:id))
        render_data(PlaylistDetailSerializer.new(playlist).serializable_hash)
      end

      def liked
        playlist = current_user.liked_songs_playlist
        render_data(playlist ? PlaylistSerializer.new(playlist).serializable_hash : nil)
      end

      def tracks
        playlist = current_user.playlists.find(params.expect(:id))
        pagy, version_tracks = paginate(playlist.current_version_tracks)
        tracks = version_tracks.map(&:track)
        render_data(
          TrackSerializer.new(tracks, params: track_genres_for(tracks)).serializable_hash,
          meta: pagy_meta(pagy),
        )
      end

      def create
        playlist = Spotify::PlaylistCreator.new(current_user, create_params).call
        render_data(PlaylistSerializer.new(playlist).serializable_hash, status: :created)
      end

      def update
        playlist = current_user.playlists.find(params.expect(:id))
        Spotify::PlaylistDetailsPusher.new(playlist, update_params).call
        render_data(PlaylistSerializer.new(playlist).serializable_hash)
      end

      private

      def create_params
        params.expect(playlist: %i[name description])
      end

      def update_params
        params.expect(playlist: %i[name description sync_enabled])
      end
    end
  end
end
