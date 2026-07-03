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

# Disable OmniAuth's built-in CSRF protection for API-only apps with separate frontends.
# OAuth has its own security via the state parameter, and the user must authorize on Spotify's site.
OmniAuth.config.request_validation_phase = nil

OmniAuth.config.on_failure = proc do |env|
  OmniAuth::FailureEndpoint.new(env).redirect_to_failure
end
