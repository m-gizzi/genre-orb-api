# frozen_string_literal: true

class ArtistGenre < ApplicationRecord
  include GenreSourced

  belongs_to :artist, inverse_of: :artist_genres
  belongs_to :genre, inverse_of: :artist_genres

  validates :artist_id, uniqueness: { scope: %i[genre_id source] }
end
