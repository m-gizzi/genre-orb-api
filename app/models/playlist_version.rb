# frozen_string_literal: true

class PlaylistVersion < ApplicationRecord
  belongs_to :playlist, inverse_of: :playlist_versions

  validates :version_number, presence: true, numericality: { only_integer: true, greater_than: 0 }
  validates :version_number, uniqueness: { scope: :playlist_id }
  validates :track_count, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  scope :recent, -> { order(version_number: :desc) }

  def self.latest
    recent.first
  end

  def self.create_snapshot(playlist)
    track_ids = playlist.playlist_tracks.order(:position).pluck(:track_id)
    next_version = playlist.playlist_versions.maximum(:version_number).to_i + 1

    create!(
      playlist: playlist,
      version_number: next_version,
      track_ids: track_ids,
      track_count: track_ids.count,
    )
  end
end
