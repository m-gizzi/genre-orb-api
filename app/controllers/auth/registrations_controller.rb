# frozen_string_literal: true

module Auth
  class RegistrationsController < Devise::RegistrationsController
    respond_to :json

    private

    def respond_with(resource, _opts = {})
      resource.persisted? ? render_success(resource) : render_errors(resource)
    end

    def render_success(resource)
      render json: { message: "Signed up successfully", user: user_data(resource) }, status: :created
    end

    def render_errors(resource)
      render json: { error: "Sign up failed", errors: resource.errors.full_messages },
             status: :unprocessable_content
    end

    def user_data(user)
      { id: user.id, email: user.email }
    end
  end
end
