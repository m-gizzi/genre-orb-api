# frozen_string_literal: true

class Playlist < ApplicationRecord
  belongs_to :user, inverse_of: :playlists
  belongs_to :current_version, class_name: "PlaylistVersion", optional: true

  before_destroy :clear_current_version

  has_many :sync_session_playlists, dependent: :destroy, inverse_of: :playlist

  has_many :playlist_versions, dependent: :destroy, inverse_of: :playlist
  alias versions playlist_versions

  has_many :smart_playlist_sources, dependent: :restrict_with_error, inverse_of: :playlist
  has_many :smart_playlists, through: :smart_playlist_sources

  has_one :smart_playlist_as_target,
          class_name: "SmartPlaylist",
          foreign_key: :target_playlist_id,
          dependent: :nullify,
          inverse_of: :target_playlist

  validates :name, presence: true
  validates :spotify_id, uniqueness: { scope: :user_id }, allow_nil: true

  scope :liked_songs, -> { where(type: "LikedSongsPlaylist") }
  scope :regular, -> { where.not(type: "LikedSongsPlaylist").or(where(type: nil)) }
  scope :sync_enabled, -> { where(sync_enabled: true) }
  scope :available, -> { where(available_on_spotify: true) }

  def tracks
    current_version&.tracks || Track.none
  end

  def current_version_tracks
    return PlaylistVersionTrack.none unless current_version

    current_version.playlist_version_tracks
                   .order(:position)
                   .includes(track: [:album, :artists, { track_genres: :genre }])
  end

  def track_count
    current_version&.track_count || 0
  end

  def liked_songs?
    false
  end

  private

  def clear_current_version
    update_columns(current_version_id: nil) if current_version_id
  end
end
