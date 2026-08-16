# frozen_string_literal: true

class User < ApplicationRecord
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable,
         :omniauthable, omniauth_providers: [:spotify]

  has_many :service_connections, dependent: :destroy, inverse_of: :user
  has_one :spotify_connection, -> { spotify }, class_name: "ServiceConnection", dependent: :destroy, inverse_of: :user

  has_many :playlists, dependent: :destroy, inverse_of: :user
  has_many :smart_playlists, through: :playlists, source: :smart_playlist_as_target
  has_many :sync_sessions, dependent: :destroy, inverse_of: :user
  has_many :artist_metadata_sessions, dependent: :destroy, inverse_of: :user

  has_many :blocked_genres, dependent: :destroy, inverse_of: :user
  has_many :track_genre_overrides, dependent: :destroy, inverse_of: :user
  has_many :artist_genre_overrides, dependent: :destroy, inverse_of: :user

  before_destroy :destroy_smart_playlists, prepend: true

  enum :registration_source, { email: 0, spotify: 1 }, validate: true

  def spotify_connected?
    spotify_connection.present?
  end

  def spotify_needs_reauth?
    spotify_connection&.needs_reauth? || false
  end

  def liked_songs_playlist
    playlists.liked_songs.first
  end

  def library_tracks
    Track.where(id: library_track_ids)
  end

  def library_artists
    Artist.where(id: TrackArtist.where(track_id: library_track_ids).select(:artist_id))
  end

  def library_albums
    Album.where(id: library_tracks.where.not(album_id: nil).select(:album_id))
  end

  def library_genres(genres = Genres::EffectiveScope.new(self))
    Genre.where(id: genres.tracks.where(track_id: library_track_ids).select(:genre_id))
  end

  private

  def destroy_smart_playlists
    SmartPlaylist.where(target_playlist_id: playlists.select(:id)).destroy_all
    playlists.reset
  end

  def current_playlist_version_ids
    playlists.where.not(current_version_id: nil).select(:current_version_id)
  end

  def library_track_ids
    PlaylistVersionTrack.where(playlist_version_id: current_playlist_version_ids).select(:track_id)
  end
end
