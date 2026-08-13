# frozen_string_literal: true

require "faraday/net_http_persistent"

module Spotify
  class Client
    BASE_URL = "https://api.spotify.com/v1"

    def initialize(token_source)
      @token = TokenSource.for(token_source)
    end

    def get(path, params: nil)
      request(:get, path, params: params)
    end

    def post(path, body: nil)
      request(:post, path, body: body)
    end

    def put(path, body: nil)
      request(:put, path, body: body)
    end

    def delete(path, body: nil)
      request(:delete, path, body: body)
    end

    private

    attr_reader :token

    def request(method, path, body: nil, params: nil)
      token.refresh! if token.expiring_soon?
      execute_request(method, path, body: body, params: params)
    rescue AuthenticationError
      token.refresh!
      retry_once(method, path, body: body, params: params)
    end

    def retry_once(method, path, body: nil, params: nil)
      execute_request(method, path, body: body, params: params)
    rescue AuthenticationError => e
      token.flag_needs_reauth!(e.message)
      raise ReauthRequiredError, e.message
    end

    def execute_request(method, path, body: nil, params: nil)
      response = self.class.connection.send(method) do |req|
        req.url path
        req.headers["Authorization"] = "Bearer #{token.access_token}"
        req.params = params if params
        req.body = body.to_json if body
      end

      handle_response(response)
    end

    def handle_response(response)
      status = response.status
      body = response.body

      case status
      when 200..299
        body
      when 401
        raise AuthenticationError, "Invalid or expired access token"
      when 429
        retry_after = response.headers["Retry-After"]
        raise RateLimitError.new(retry_after: retry_after, user_id: token.user_id)
      else
        raise ApiError, "Spotify API error (#{status}): #{body}"
      end
    end

    class << self
      def connection
        @connection ||= Faraday.new(url: BASE_URL) do |conn|
          conn.request :json
          conn.response :json, content_type: /\bjson$/
          conn.adapter :net_http_persistent, pool_size: 10
        end
      end
    end
  end
end
