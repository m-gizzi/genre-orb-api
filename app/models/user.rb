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

  enum :registration_source, { email: 0, spotify: 1 }, validate: true

  def spotify_connected?
    spotify_connection.present?
  end

  def liked_songs_playlist
    playlists.liked_songs.first
  end
end
