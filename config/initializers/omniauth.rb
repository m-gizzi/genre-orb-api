# frozen_string_literal: true

SPOTIFY_SCOPES = %w[
  playlist-read-private
  playlist-read-collaborative
  playlist-modify-public
  playlist-modify-private
  user-library-read
  user-read-private
  user-read-email
].freeze

Rails.application.config.middleware.use OmniAuth::Builder do
  provider :spotify,
           Rails.application.credentials.dig(:spotify, :client_id),
           Rails.application.credentials.dig(:spotify, :client_secret),
           scope: SPOTIFY_SCOPES.join(" ")
end

OmniAuth.config.logger = Rails.logger
OmniAuth.config.allowed_request_methods = [:post]

# The redirect_uri Spotify sends the browser back to. OmniAuth otherwise derives
# it from the request, which is wrong behind a proxy: the browser's scheme and
# host are the tunnel's, but the request Rails receives carries the proxy's. Set
# this to the public origin whenever the API is not reached directly, and
# register the same origin's /auth/spotify/callback with Spotify. Unset, OmniAuth
# keeps deriving it from the request.
OmniAuth.config.full_host = ENV["OAUTH_PUBLIC_URL"].presence

# Disable OmniAuth's built-in CSRF protection for API-only apps with separate frontends.
# OAuth has its own security via the state parameter, and the user must authorize on Spotify's site.
OmniAuth.config.request_validation_phase = nil

OmniAuth.config.on_failure = proc do |env|
  OmniAuth::FailureEndpoint.new(env).redirect_to_failure
end
