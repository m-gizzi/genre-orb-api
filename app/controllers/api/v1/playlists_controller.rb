# frozen_string_literal: true

module Api
  module V1
    class PlaylistsController < BaseController
      def index
        playlists = current_user.playlists
                                .includes(:current_version)
                                .where(available_on_spotify: true)
                                .order(:name)

        render json: PlaylistSerializer.new(playlists).serialize
      end

      def update
        playlist = current_user.playlists.find(params.expect(:id))
        playlist.update!(playlist_params)

        render json: PlaylistSerializer.new(playlist).serialize
      end

      private

      def playlist_params
        params.expect(playlist: [:sync_enabled])
      end
    end
  end
end
