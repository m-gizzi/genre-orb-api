# frozen_string_literal: true

module Auth
  class UsersController < ApplicationController
    before_action :authenticate_user!

    def me
      render json: {
        user: {
          id: current_user.id,
          email: current_user.email,
          spotify_connected: current_user.spotify_connected?,
          spotify_profile: current_user.spotify_connection&.profile_data,
        },
      }
    end
  end
end
