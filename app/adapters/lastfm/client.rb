# frozen_string_literal: true

require "faraday/net_http_persistent"

module Lastfm
  class Client
    BASE_URL = "https://ws.audioscrobbler.com/2.0/"

    # Last.fm's own error numbers. It answers most failures with HTTP 200 and one of
    # these in the body, so the status line alone says nothing.
    ERROR_NOT_FOUND = 6
    ERROR_RATE_LIMIT = 29
    ERROR_INVALID_KEY = 10
    ERROR_SUSPENDED_KEY = 26

    def get(method, params: {})
      response = self.class.connection.get do |req|
        req.params = params.merge(method: method, api_key: self.class.api_key, format: "json")
      end

      handle_response(response)
    end

    private

    def handle_response(response)
      body = response.body
      raise ApiError, "Last.fm API error (#{response.status}): #{body}" unless response.status.between?(200, 299)

      # A Hash is the only shape carrying an error; anything else is a success body.
      raise_body_error(body) if body.is_a?(Hash) && body["error"].present?

      body
    end

    def raise_body_error(body)
      code = body["error"].to_i
      message = "Last.fm error #{code}: #{body["message"]}"

      case code
      when ERROR_NOT_FOUND then raise NotFoundError, message
      when ERROR_RATE_LIMIT then raise RateLimitError, message
      when ERROR_INVALID_KEY, ERROR_SUSPENDED_KEY then raise ConfigurationError, message
      else raise ApiError, message
      end
    end

    class << self
      def connection
        @connection ||= Faraday.new(url: BASE_URL) do |conn|
          conn.response :json, content_type: /\bjson$/
          conn.adapter :net_http_persistent, pool_size: 2
        end
      end

      def api_key
        @api_key ||= begin
          key = Rails.application.credentials.dig(:lastfm, :api_key)
          raise ConfigurationError, "lastfm.api_key is not configured" if key.blank?

          key
        end
      end
    end
  end
end
