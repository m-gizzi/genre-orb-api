# frozen_string_literal: true

class Artist < ApplicationRecord
  has_many :album_artists, dependent: :destroy, inverse_of: :artist
  has_many :albums, through: :album_artists

  has_many :track_artists, dependent: :destroy, inverse_of: :artist
  has_many :tracks, through: :track_artists

  has_many :artist_genres, dependent: :destroy, inverse_of: :artist
  has_many :genres, through: :artist_genres

  METADATA_TTL = 7.days

  scope :synced, -> { where.not(metadata_fetched_at: nil) }
  scope :needs_metadata, lambda {
    where("metadata_fetched_at IS NULL OR metadata_fetched_at < ?", METADATA_TTL.ago)
      .order(Arel.sql("metadata_fetched_at ASC NULLS FIRST"))
  }

  validates :name, presence: true
  validates :spotify_id, uniqueness: true
end
