# frozen_string_literal: true

module Lastfm
  # Last.fm error 29, "rate limit exceeded". It publishes no limit and sends no
  # Retry-After, only a warning that sustained multi-request-per-second traffic gets
  # an account suspended, so the backoff is deliberately generous.
  class RateLimitError < ApiError
    RETRY_AFTER = 30

    def retry_after = RETRY_AFTER
  end
end
