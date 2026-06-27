# frozen_string_literal: true

class ApplicationController < ActionController::API
  include ActionController::Cookies

  respond_to :json

  private

  def authenticate_user!
    return if user_signed_in?

    render json: { error: "You need to sign in or sign up before continuing" }, status: :unauthorized
  end
end
