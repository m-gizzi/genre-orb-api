# frozen_string_literal: true

module Lastfm
  # Last.fm error 6, "artist not found". An expected outcome, not a failure.
  class NotFoundError < ApiError; end
end
