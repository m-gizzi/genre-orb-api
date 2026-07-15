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

      def tracks
        playlist = current_user.playlists.find(params.expect(:id))
        pagy, version_tracks = paginate(playlist_version_tracks(playlist))
        tracks = version_tracks.map(&:track)
        render_data(TrackSerializer.new(tracks).serializable_hash, meta: pagy_meta(pagy))
      end

      def update
        playlist = current_user.playlists.find(params.expect(:id))
        playlist.update!(playlist_params)
        render_data(PlaylistSerializer.new(playlist).serializable_hash)
      end

      private

      def playlist_version_tracks(playlist)
        version = playlist.current_version
        return PlaylistVersionTrack.none unless version

        version.playlist_version_tracks
               .order(:position)
               .includes(track: [:album, :artists, { track_genres: :genre }])
      end

      def playlist_params
        params.expect(playlist: [:sync_enabled])
      end
    end
  end
end
