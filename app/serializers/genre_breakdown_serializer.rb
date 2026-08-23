# frozen_string_literal: true

# `track_count` comes from a Genres::TrackCounts lookup passed as params, not from the
# genre itself: how many tracks carry it depends on the track set being described.
class GenreBreakdownSerializer < GenreSerializer
  attribute :track_count do |genre|
    params.fetch(:track_counts, {}).fetch(genre.id, 0)
  end
end
