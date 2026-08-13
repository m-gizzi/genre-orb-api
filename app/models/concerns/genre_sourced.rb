# frozen_string_literal: true

module GenreSourced
  extend ActiveSupport::Concern

  # Genres::TrackGenreDeriver copies artist_genres.source into track_genres.source
  # as a raw integer inside one SQL statement, so these values drifting between the
  # two models is silent data corruption rather than a test failure. One map.
  SOURCES = { spotify: 0, user: 1, musicbrainz: 2, lastfm: 3 }.freeze

  # The sources the enrichment drip owns. `spotify` belongs to the nightly artist
  # metadata stage and `user` only ever to a person.
  ENRICHMENT_SOURCES = %i[musicbrainz lastfm].freeze

  included do
    enum :source, SOURCES, validate: true

    validates :confidence,
              numericality: {
                greater_than_or_equal_to: 0.0,
                less_than_or_equal_to: 1.0,
              }
  end
end
