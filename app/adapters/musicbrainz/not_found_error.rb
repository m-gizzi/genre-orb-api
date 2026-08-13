# frozen_string_literal: true

module Musicbrainz
  # An expected outcome, not a failure: MusicBrainz simply does not know this
  # resource. The drip records the row `unmatched` and revisits it much later.
  class NotFoundError < ApiError; end
end
