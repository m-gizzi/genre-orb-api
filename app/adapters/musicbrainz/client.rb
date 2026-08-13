# frozen_string_literal: true

require "faraday/net_http_persistent"

module Musicbrainz
  # No token, no refresh, no retry — MusicBrainz is anonymous and read-only. The only
  # obligation is identifying ourselves; the only interesting status is 503, which is
  # how it says "you are going too fast".
  class Client
    BASE_URL = "https://musicbrainz.org/ws/2"
    VERSION = "0.1"

    def get(path, params: {})
      response = self.class.connection.get(path) do |req|
        req.params = params.merge(fmt: "json")
        req.headers["User-Agent"] = self.class.user_agent
      end

      handle_response(response)
    end

    private

    def handle_response(response)
      case response.status
      when 200..299 then response.body
      when 404 then raise NotFoundError, "Not found in MusicBrainz"
      when 503 then raise RateLimitError, "MusicBrainz is throttling this client"
      else raise ApiError, "MusicBrainz API error (#{response.status}): #{response.body}"
      end
    end

    class << self
      def connection
        # FlatParamsEncoder is required, not cosmetic: the batched url lookup sends
        # `resource=a&resource=b`, and Faraday's default encoder would turn an array
        # into `resource[]=a`, which MusicBrainz does not understand.
        @connection ||= Faraday.new(url: BASE_URL,
                                    request: { params_encoder: Faraday::FlatParamsEncoder },) do |conn|
          conn.response :json, content_type: /\bjson$/
          conn.adapter :net_http_persistent, pool_size: 2
        end
      end

      # Required by MusicBrainz: requests without enough information to contact the
      # application maintainer are throttled far harder than 1 req/s.
      def user_agent
        @user_agent ||= "GenreOrb/#{VERSION} ( #{contact} )"
      end

      private

      def contact
        configured = Rails.application.credentials.dig(:musicbrainz, :contact)
        raise ConfigurationError, "musicbrainz.contact is not configured" if configured.blank?

        configured
      end
    end
  end
end
