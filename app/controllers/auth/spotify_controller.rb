# frozen_string_literal: true

module Auth
  class SpotifyController < ApplicationController
    before_action :authenticate_user!

    def destroy
      connection = current_user.spotify_connection

      if connection
        connection.destroy!
        render json: { message: "Spotify account disconnected" }
      else
        render json: { error: "No Spotify account connected" }, status: :not_found
      end
    end
  end
end
