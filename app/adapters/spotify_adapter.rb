# frozen_string_literal: true

class SpotifyAdapter
  BASE_URL = "https://api.spotify.com/v1"
  TOKEN_URL = "https://accounts.spotify.com/api/token"

  class AuthenticationError < StandardError; end
  class TokenRefreshError < StandardError; end
  class ApiError < StandardError; end

  class RateLimitError < ApiError
    attr_reader :retry_after, :user_id

    def initialize(message = nil, retry_after: 0, user_id: nil)
      @retry_after = retry_after.to_i
      @user_id = user_id
      super(message || "Rate limited, retry after #{@retry_after}s")
    end
  end

  def initialize(service_connection)
    @service_connection = service_connection
  end

  def user_profile
    request(:get, "me")
  end

  def verify_connection
    user_profile
    true
  rescue AuthenticationError
    false
  end

  def playlists(limit: 50, offset: 0)
    request(:get, "me/playlists", params: { limit: limit, offset: offset })
  end

  def playlist(playlist_id)
    request(:get, "playlists/#{playlist_id}")
  end

  def playlist_tracks(playlist_id, limit: 100, offset: 0)
    request(:get, "playlists/#{playlist_id}/tracks", params: { limit: limit, offset: offset })
  end

  def liked_songs(limit: 50, offset: 0)
    request(:get, "me/tracks", params: { limit: limit, offset: offset })
  end

  private

  attr_reader :service_connection

  def request(method, path, body: nil, params: nil)
    ensure_valid_token!
    execute_request(method, path, body: body, params: params)
  rescue AuthenticationError
    refresh_token!
    execute_request(method, path, body: body, params: params)
  end

  def execute_request(method, path, body: nil, params: nil)
    response = build_connection.send(method) do |req|
      req.url path
      req.params = params if params
      req.body = body.to_json if body
    end

    handle_response(response)
  end

  def build_connection
    Faraday.new(url: BASE_URL) do |conn|
      conn.request :json
      conn.response :json, content_type: /\bjson$/
      conn.adapter Faraday.default_adapter
      conn.headers["Authorization"] = "Bearer #{service_connection.access_token}"
    end
  end

  def ensure_valid_token!
    refresh_token! if service_connection.token_expiring_soon?
  end

  def refresh_token!
    data = fetch_refreshed_token
    update_service_connection(data)
  end

  def fetch_refreshed_token
    response = Faraday.post(TOKEN_URL) do |req|
      req.headers["Content-Type"] = "application/x-www-form-urlencoded"
      req.body = refresh_token_body
    end

    body = response.body
    raise TokenRefreshError, "Failed to refresh token: #{body}" unless response.success?

    JSON.parse(body)
  end

  def refresh_token_body
    URI.encode_www_form(
      grant_type: "refresh_token",
      refresh_token: service_connection.refresh_token,
      client_id: self.class.spotify_client_id,
      client_secret: self.class.spotify_client_secret,
    )
  end

  def update_service_connection(data)
    service_connection.update!(
      access_token: data["access_token"],
      refresh_token: data["refresh_token"] || service_connection.refresh_token,
      token_expires_at: Time.current + data["expires_in"].to_i.seconds,
    )
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
      raise RateLimitError.new(retry_after: retry_after, user_id: service_connection.user_id)
    else
      raise ApiError, "Spotify API error (#{status}): #{body}"
    end
  end

  class << self
    def spotify_client_id
      Rails.application.credentials.dig(:spotify, :client_id)
    end

    def spotify_client_secret
      Rails.application.credentials.dig(:spotify, :client_secret)
    end
  end
end
