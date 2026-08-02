# frozen_string_literal: true

module Spotify
  class PlaylistCreator
    attr_reader :user, :attributes

    def initialize(user, attributes)
      @user = user
      @attributes = attributes
    end

    def call
      playlist = user.playlists.new(local_attributes)
      playlist.validate!

      playlist.spotify_id = create_on_spotify.fetch("id")
      playlist.save!
      playlist
    end

    private

    def local_attributes
      attributes.slice(:name, :description, :is_public).merge(
        sync_enabled: true,
        available_on_spotify: true,
      )
    end

    def create_on_spotify
      connection = user.spotify_connection
      SpotifyAdapter.new(connection).create_playlist(
        connection.service_user_id,
        name: attributes[:name],
        description: attributes[:description].presence,
        public: ActiveModel::Type::Boolean.new.cast(attributes[:is_public]) || false,
      )
    end
  end
end
