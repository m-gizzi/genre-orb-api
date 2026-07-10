# frozen_string_literal: true

class PlaylistVersion < ApplicationRecord
  belongs_to :playlist, inverse_of: :playlist_versions

  has_many :playlist_version_tracks, dependent: :destroy, inverse_of: :playlist_version
  has_many :tracks, through: :playlist_version_tracks

  enum :status, {
    building: 0,
    complete: 1,
  }

  validates :version_number, presence: true, numericality: { only_integer: true, greater_than: 0 }
  validates :version_number, uniqueness: { scope: :playlist_id }
  validates :track_count, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  def self.create_for_sync!(playlist)
    next_version = (playlist.versions.maximum(:version_number) || 0) + 1
    create!(playlist: playlist, version_number: next_version, track_count: 0)
  end
end
