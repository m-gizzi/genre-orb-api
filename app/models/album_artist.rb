# frozen_string_literal: true

class AlbumArtist < ApplicationRecord
  belongs_to :album, inverse_of: :album_artists
  belongs_to :artist, inverse_of: :album_artists

  validates :album_id, uniqueness: { scope: :artist_id }
end
