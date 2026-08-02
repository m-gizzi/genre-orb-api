# frozen_string_literal: true

module Spotify
  class PlaylistDetailsPusher
    MIRRORED_ATTRIBUTES = %w[name description is_public].freeze

    SPOTIFY_KEYS = {
      "name" => :name,
      "description" => :description,
      "is_public" => :public,
    }.freeze

    attr_reader :playlist, :attributes

    def initialize(playlist, attributes)
      @playlist = playlist
      @attributes = attributes
    end

    def call
      playlist.assign_attributes(attributes)
      playlist.validate!

      push_to_spotify if push_required?
      playlist.save!
      playlist
    end

    private

    def push_required?
      playlist.spotify_id.present? && changed_mirrored_attributes.any?
    end

    def changed_mirrored_attributes
      playlist.changed & MIRRORED_ATTRIBUTES
    end

    def push_to_spotify
      payload = changed_mirrored_attributes.to_h do |attribute|
        [SPOTIFY_KEYS.fetch(attribute), spotify_value(attribute)]
      end

      SpotifyAdapter.new(playlist.user.spotify_connection)
                    .update_playlist_details(playlist.spotify_id, payload)
    end

    def spotify_value(attribute)
      value = playlist.public_send(attribute)
      attribute == "description" ? value.to_s : value
    end
  end
end
