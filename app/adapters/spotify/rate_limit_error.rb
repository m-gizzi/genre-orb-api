# frozen_string_literal: true

module Spotify
  class RateLimitError < ApiError
    # Spotify should always send a Retry-After header on a 429, but if it is
    # missing (or zero) we still need a positive pause so Redis SETEX is valid.
    MIN_RETRY_AFTER = 1

    attr_reader :retry_after, :user_id

    def initialize(message = nil, retry_after: nil, user_id: nil)
      @retry_after = [retry_after.to_i, MIN_RETRY_AFTER].max
      @user_id = user_id
      super(message || "Rate limited, retry after #{@retry_after}s")
    end
  end
end
