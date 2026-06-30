# frozen_string_literal: true

module Auth
  class OmniauthCallbacksController < Devise::OmniauthCallbacksController
    def spotify
      auth = request.env["omniauth.auth"]
      origin = request.env["omniauth.origin"]

      unless valid_origin?(origin)
        Rails.logger.warn("Invalid OAuth origin attempted: #{origin}")
        head :bad_request
        return
      end

      result = SpotifyOauthService.new(current_user, auth).call

      sign_in(result.user) if result.success? && !user_signed_in?

      redirect_to build_callback_url(origin, success: result.success?, error: result.error), allow_other_host: true
    end

    def failure
      origin = request.env["omniauth.origin"]
      error_code = params[:error]
      error_message = I18n.t(error_code, scope: "oauth.errors", default: I18n.t("oauth.errors.default"))

      unless valid_origin?(origin)
        Rails.logger.warn("Invalid OAuth origin in failure callback: #{origin}")
        head :bad_request
        return
      end

      redirect_to build_callback_url(origin, success: false, error: error_message), allow_other_host: true
    end

    private

    def build_callback_url(origin, success:, error: nil)
      uri = URI.parse(origin)

      params = { success: success }
      params[:error] = error if error.present?
      uri.query = URI.encode_www_form(params)

      uri.to_s
    end

    def valid_origin?(origin)
      return false if origin.blank?

      uri = URI.parse(origin)
      host_with_port = uri.port == uri.default_port ? uri.host : "#{uri.host}:#{uri.port}"

      allowed_origins.include?(host_with_port)
    rescue URI::InvalidURIError
      false
    end

    def allowed_origins
      ENV.fetch("ALLOWED_OAUTH_ORIGINS").split(",").map(&:strip)
    end
  end
end
