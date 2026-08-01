# frozen_string_literal: true

class ArtistGenre < ApplicationRecord
  belongs_to :artist, inverse_of: :artist_genres
  belongs_to :genre, inverse_of: :artist_genres

  validates :artist_id, uniqueness: { scope: :genre_id }
end
