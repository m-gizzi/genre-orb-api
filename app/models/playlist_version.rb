# frozen_string_literal: true

class PlaylistVersion < ApplicationRecord
  belongs_to :playlist, inverse_of: :playlist_versions

  has_many :playlist_version_tracks, dependent: :destroy, inverse_of: :playlist_version
  has_many :tracks, through: :playlist_version_tracks

  has_one :playlist_as_current,
          class_name: "Playlist",
          foreign_key: :current_version_id,
          dependent: nil,
          inverse_of: :current_version

  enum :status, {
    building: 0,
    complete: 1,
  }

  enum :source, {
    spotify_sync: 0,
    rule_evaluation: 1,
  }, prefix: true

  validates :version_number, presence: true, numericality: { only_integer: true, greater_than: 0 }
  validates :version_number, uniqueness: { scope: :playlist_id }
  validates :track_count, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  def self.create_for_sync!(playlist, spotify_snapshot_id: nil)
    create_next!(playlist, source: :spotify_sync, spotify_snapshot_id: spotify_snapshot_id)
  end

  def self.create_for_push!(playlist)
    create_next!(playlist, source: :rule_evaluation)
  end

  def self.create_next!(playlist, source:, spotify_snapshot_id: nil)
    playlist.with_lock do
      next_version = (playlist.versions.maximum(:version_number) || 0) + 1
      create!(playlist: playlist, version_number: next_version, track_count: 0, source: source,
              spotify_snapshot_id: spotify_snapshot_id,)
    end
  end
  private_class_method :create_next!
end
