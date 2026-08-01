# frozen_string_literal: true

module Api
  module V1
    class PlaylistsController < BaseController
      def index
        scope = Playlists::Filter.new(current_user, params).call

        pagy, playlists = paginate(scope)
        render_data(PlaylistSerializer.new(playlists).serializable_hash, meta: pagy_meta(pagy))
      end

      def show
        playlist = current_user.playlists.includes(:current_version).find(params.expect(:id))
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
        render_data(TrackSerializer.new(tracks).serializable_hash, meta: pagy_meta(pagy))
      end

      def update
        playlist = current_user.playlists.find(params.expect(:id))
        playlist.update!(playlist_params)
        render_data(PlaylistSerializer.new(playlist).serializable_hash)
      end

      private

      def playlist_params
        params.expect(playlist: [:sync_enabled])
      end
    end
  end
end
