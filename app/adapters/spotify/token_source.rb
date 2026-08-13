# frozen_string_literal: true

module Spotify
  module TokenSource
    TOKEN_URL = "https://accounts.spotify.com/api/token"

    class << self
      def for(source)
        return UserToken.new(source) if source.is_a?(ServiceConnection)
        raise AuthenticationError, "Spotify is not connected" unless source

        source
      end

      def request(grant)
        Faraday.post(TOKEN_URL) do |req|
          req.headers["Content-Type"] = "application/x-www-form-urlencoded"
          req.body = URI.encode_www_form(grant.merge(client_id: client_id, client_secret: client_secret))
        end
      end

      def client_id
        Rails.application.credentials.dig(:spotify, :client_id)
      end

      def client_secret
        Rails.application.credentials.dig(:spotify, :client_secret)
      end
    end
  end
end
