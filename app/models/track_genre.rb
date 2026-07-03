# frozen_string_literal: true

class TrackGenre < ApplicationRecord
  belongs_to :track, inverse_of: :track_genres
  belongs_to :genre, inverse_of: :track_genres

  validates :track_id, uniqueness: { scope: :genre_id }
  validates :confidence,
            numericality: {
              greater_than_or_equal_to: 0.0,
              less_than_or_equal_to: 1.0,
            }
end
