# frozen_string_literal: true

class TrackGenre < ApplicationRecord
  include GenreSourced

  belongs_to :track, inverse_of: :track_genres
  belongs_to :genre, inverse_of: :track_genres

  validates :track_id, uniqueness: { scope: %i[genre_id source] }
end
