# frozen_string_literal: true

class Playlist < ApplicationRecord
  belongs_to :user, inverse_of: :playlists

  has_many :playlist_tracks, dependent: :destroy, inverse_of: :playlist
  has_many :tracks, through: :playlist_tracks

  has_many :playlist_versions, dependent: :destroy, inverse_of: :playlist

  has_many :smart_playlist_sources, dependent: :restrict_with_error, inverse_of: :playlist
  has_many :smart_playlists, through: :smart_playlist_sources

  has_one :smart_playlist_as_target,
          class_name: "SmartPlaylist",
          foreign_key: :target_playlist_id,
          dependent: :nullify,
          inverse_of: :target_playlist

  validates :name, presence: true
  validates :spotify_id, uniqueness: true, allow_nil: true
  validates :track_count, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :only_one_liked_songs_per_user, if: :is_liked_songs?

  scope :liked_songs, -> { where(is_liked_songs: true) }
  scope :regular, -> { where(is_liked_songs: false) }
  scope :with_spotify, -> { where.not(spotify_id: nil) }

  def ordered_tracks
    tracks.joins(:playlist_tracks)
          .where(playlist_tracks: { playlist_id: id })
          .order("playlist_tracks.position")
  end

  private

  def only_one_liked_songs_per_user
    existing = Playlist.where(user_id: user_id, is_liked_songs: true)
    existing = existing.where.not(id: id) if persisted?

    errors.add(:is_liked_songs, "playlist already exists for this user") if existing.exists?
  end
end
