# frozen_string_literal: true

module Auth
  class OmniauthCallbacksController < Devise::OmniauthCallbacksController
    class InvalidOauthOriginError < StandardError; end

    rescue_from InvalidOauthOriginError, with: :handle_invalid_origin

    def spotify
      ensure_valid_oauth_origin!

      result = SpotifyOauthService.new(current_user, omniauth_auth).call
      sign_in(result.user) if result.success? && !user_signed_in?

      redirect_to build_callback_url(omniauth_origin, success: result.success?, error: result.error),
                  allow_other_host: true
    end

    def failure
      ensure_valid_oauth_origin!

      error_message = I18n.t(params[:error], scope: "oauth.errors", default: I18n.t("oauth.errors.default"))
      redirect_to build_callback_url(omniauth_origin, success: false, error: error_message), allow_other_host: true
    end

    private

    def ensure_valid_oauth_origin!
      raise InvalidOauthOriginError unless valid_origin?(omniauth_origin)
    end

    def handle_invalid_origin
      Rails.logger.warn("Invalid OAuth origin attempted: #{omniauth_origin}")
      head :bad_request
    end

    def omniauth_auth
      request.env["omniauth.auth"]
    end

    def omniauth_origin
      request.env["omniauth.origin"]
    end

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
      ENV.fetch("ALLOWED_OAUTH_ORIGINS", "").split(",").map(&:strip).reject(&:blank?)
    end
  end
end
