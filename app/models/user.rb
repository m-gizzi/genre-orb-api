# frozen_string_literal: true

class User < ApplicationRecord
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable,
         :omniauthable, omniauth_providers: [:spotify]

  has_many :service_connections, dependent: :destroy, inverse_of: :user
  has_one :spotify_connection, -> { spotify }, class_name: "ServiceConnection", dependent: :destroy, inverse_of: :user

  has_many :playlists, dependent: :destroy, inverse_of: :user
  has_many :smart_playlists, dependent: :destroy, inverse_of: :user
  has_many :sync_sessions, dependent: :destroy, inverse_of: :user
  has_many :artist_metadata_sessions, dependent: :destroy, inverse_of: :user

  enum :registration_source, { email: 0, spotify: 1 }, validate: true

  def spotify_connected?
    spotify_connection.present?
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

  def library_genres
    Genre.where(id: TrackGenre.where(track_id: library_track_ids).select(:genre_id))
  end

  private

  def current_playlist_version_ids
    playlists.where.not(current_version_id: nil).select(:current_version_id)
  end

  def library_track_ids
    PlaylistVersionTrack.where(playlist_version_id: current_playlist_version_ids).select(:track_id)
  end
end
