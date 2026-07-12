# frozen_string_literal: true

class ApplicationController < ActionController::API
  include ActionController::Cookies

  respond_to :json

  private

  def authenticate_user!
    return if user_signed_in?

    render json: {
      errors: [{ code: "unauthenticated", message: I18n.t("api.errors.unauthenticated") }],
    }, status: :unauthorized
  end
end
