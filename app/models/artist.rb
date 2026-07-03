# frozen_string_literal: true

class Artist < ApplicationRecord
  has_many :album_artists, dependent: :destroy, inverse_of: :artist
  has_many :albums, through: :album_artists

  has_many :track_artists, dependent: :destroy, inverse_of: :artist
  has_many :tracks, through: :track_artists

  validates :name, presence: true
  validates :spotify_id, uniqueness: true
end
