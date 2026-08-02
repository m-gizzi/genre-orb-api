# frozen_string_literal: true

module SpotifyErrorRendering
  extend ActiveSupport::Concern

  included do
    rescue_from SpotifyAdapter::ApiError, with: :render_spotify_unavailable
    rescue_from SpotifyAdapter::AuthenticationError, with: :render_spotify_not_connected
    rescue_from SpotifyAdapter::TokenRefreshError, with: :render_spotify_not_connected
    rescue_from SpotifyAdapter::RateLimitError, with: :render_spotify_rate_limited
  end

  private

  def render_spotify_rate_limited(exception)
    response.set_header("Retry-After", exception.retry_after.to_s)
    render_error(
      I18n.t("api.errors.spotify_rate_limited"),
      status: :too_many_requests,
      code: "spotify_rate_limited",
    )
  end

  def render_spotify_unavailable(exception)
    Rails.logger.error("Spotify write failed: #{exception.message}")
    render_error(
      I18n.t("api.errors.spotify_unavailable"),
      status: :bad_gateway,
      code: "spotify_unavailable",
    )
  end

  def render_spotify_not_connected
    render_error(
      I18n.t("api.errors.spotify_not_connected"),
      status: :unprocessable_content,
      code: "spotify_not_connected",
    )
  end
end
