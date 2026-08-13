# frozen_string_literal: true

module Musicbrainz
  # MusicBrainz signals throttling with a bare 503 and sends no Retry-After, so the
  # backoff is ours to choose rather than theirs to dictate.
  class RateLimitError < ApiError
    RETRY_AFTER = 5

    def retry_after = RETRY_AFTER
  end
end
