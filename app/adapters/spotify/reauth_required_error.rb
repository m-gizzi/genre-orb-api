# frozen_string_literal: true

module Spotify
  # A refresh that cannot succeed no matter how often it is retried — the user
  # revoked access, or the refresh token was rotated away. A subclass of
  # TokenRefreshError so the controllers' existing rescue keeps rendering it.
  class ReauthRequiredError < TokenRefreshError; end
end
