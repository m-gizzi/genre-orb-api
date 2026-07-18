# frozen_string_literal: true

class Album < ApplicationRecord
  has_many :album_artists, dependent: :destroy, inverse_of: :album
  has_many :artists, through: :album_artists

  has_many :tracks, dependent: :destroy, inverse_of: :album

  scope :for_artist, ->(artist) { where(id: artist.album_ids) }
  scope :by_release_year, -> { order(arel_table[:release_year].asc.nulls_last) }

  validates :title, presence: true
  validates :spotify_id, uniqueness: true
  validates :release_year,
            numericality: {
              only_integer: true,
            },
            allow_nil: true
  validates :total_tracks,
            numericality: { only_integer: true, greater_than: 0 },
            allow_nil: true
end
