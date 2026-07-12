# frozen_string_literal: true

class Track < ApplicationRecord
  belongs_to :album, inverse_of: :tracks

  has_many :track_artists, dependent: :destroy, inverse_of: :track
  has_many :artists, through: :track_artists

  has_many :track_genres, dependent: :destroy, inverse_of: :track
  has_many :genres, through: :track_genres

  has_many :playlist_version_tracks, dependent: :destroy, inverse_of: :track
  has_many :playlist_versions, through: :playlist_version_tracks

  scope :with_catalog_associations, -> { includes(:album, :artists, track_genres: :genre) }

  validates :title, presence: true
  validates :spotify_id, uniqueness: true, allow_nil: true
  validates :duration_ms,
            numericality: { only_integer: true, greater_than: 0 },
            allow_nil: true
  validates :track_number,
            numericality: { only_integer: true, greater_than: 0 },
            allow_nil: true
  validates :popularity,
            numericality: {
              only_integer: true,
              greater_than_or_equal_to: 0,
              less_than_or_equal_to: 100,
            },
            allow_nil: true
end
