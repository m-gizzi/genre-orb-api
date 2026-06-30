# frozen_string_literal: true

class SpotifyAdapter
  BASE_URL = "https://api.spotify.com/v1"
  TOKEN_URL = "https://accounts.spotify.com/api/token"

  class AuthenticationError < StandardError; end
  class TokenRefreshError < StandardError; end
  class ApiError < StandardError; end
  class RateLimitError < ApiError; end

  def initialize(service_connection)
    @service_connection = service_connection
  end

  def user_profile
    request(:get, "/me")
  end

  def verify_connection
    user_profile
    true
  rescue AuthenticationError
    false
  end

  private

  attr_reader :service_connection

  def request(method, path, body: nil, params: nil, retry_on_401: true)
    ensure_valid_token!

    response = connection.send(method) do |req|
      req.url path
      req.params = params if params
      req.body = body.to_json if body
    end

    handle_response(response)
  rescue AuthenticationError
    raise unless retry_on_401

    refresh_token!
    request(method, path, body: body, params: params, retry_on_401: false)
  end

  def connection
    @connection ||= build_connection
  end

  def build_connection
    Faraday.new(url: BASE_URL) do |faraday|
      faraday.request :json
      faraday.response :json, content_type: /\bjson$/
      faraday.adapter Faraday.default_adapter
      faraday.headers["Authorization"] = "Bearer #{service_connection.access_token}"
    end
  end

  def ensure_valid_token!
    refresh_token! if service_connection.token_expiring_soon?
  end

  def refresh_token!
    response = Faraday.post(TOKEN_URL) do |req|
      req.headers["Content-Type"] = "application/x-www-form-urlencoded"
      req.body = URI.encode_www_form(
        grant_type: "refresh_token",
        refresh_token: service_connection.refresh_token,
        client_id: spotify_client_id,
        client_secret: spotify_client_secret,
      )
    end

    raise TokenRefreshError, "Failed to refresh token: #{response.body}" unless response.success?

    data = JSON.parse(response.body)
    service_connection.update!(
      access_token: data["access_token"],
      refresh_token: data["refresh_token"] || service_connection.refresh_token,
      token_expires_at: Time.current + data["expires_in"].to_i.seconds,
    )

    @connection = nil
  end

  def handle_response(response)
    case response.status
    when 200..299
      response.body
    when 401
      raise AuthenticationError, "Invalid or expired access token"
    when 429
      retry_after = response.headers["Retry-After"]
      raise RateLimitError, "Rate limited. Retry after: #{retry_after} seconds"
    else
      raise ApiError, "Spotify API error (#{response.status}): #{response.body}"
    end
  end

  def spotify_client_id
    Rails.application.credentials.dig(:spotify, :client_id)
  end

  def spotify_client_secret
    Rails.application.credentials.dig(:spotify, :client_secret)
  end
end
