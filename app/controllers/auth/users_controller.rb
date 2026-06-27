# frozen_string_literal: true

module Auth
  class UsersController < ApplicationController
    before_action :authenticate_user!

    def me
      render json: {
        user: {
          id: current_user.id,
          email: current_user.email,
        },
      }
    end
  end
end
