# frozen_string_literal: true

module Api
  module V1
    class PlaylistsController < BaseController
      def index
        playlists = current_user.playlists
                                .where(available_on_spotify: true)
                                .order(:name)

        render json: PlaylistSerializer.new(playlists).serialize
      end

      def update
        playlist = current_user.playlists.find(params[:id])
        playlist.update!(playlist_params)

        render json: PlaylistSerializer.new(playlist).serialize
      end

      private

      def playlist_params
        params.require(:playlist).permit(:sync_enabled)
      end
    end
  end
end
