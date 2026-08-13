# frozen_string_literal: true

module Spotify
  class UserToken
    ERROR_LIMIT = 250

    delegate :access_token, :user_id, to: :service_connection

    def initialize(service_connection)
      @service_connection = service_connection
    end

    def expiring_soon?
      service_connection.token_expiring_soon?
    end

    def refresh!
      raise reauth_required("Spotify refresh token is missing") if service_connection.refresh_token.blank?

      response = TokenSource.request(grant_type: "refresh_token", refresh_token: service_connection.refresh_token)
      raise refresh_error(response) unless response.success?

      store(JSON.parse(response.body))
    end

    def flag_needs_reauth!(message)
      service_connection.update_columns(
        needs_reauth: true,
        last_auth_error: message.to_s.truncate(ERROR_LIMIT),
        last_auth_error_at: Time.current,
        updated_at: Time.current,
      )
    end

    private

    attr_reader :service_connection

    def refresh_error(response)
      message = "Failed to refresh token: #{response.body}"
      return TokenRefreshError.new(message) unless response.status.in?(400..499)

      reauth_required(message)
    end

    def reauth_required(message)
      flag_needs_reauth!(message)
      ReauthRequiredError.new(message)
    end

    def store(data)
      service_connection.update!(
        access_token: data["access_token"],
        refresh_token: data["refresh_token"] || service_connection.refresh_token,
        token_expires_at: Time.current + data["expires_in"].to_i.seconds,
      )
    end
  end
end
