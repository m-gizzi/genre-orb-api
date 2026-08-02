# frozen_string_literal: true

class PlaylistSerializer
  include Alba::Resource

  attributes :id, :name, :description, :spotify_id, :is_public,
             :sync_enabled, :available_on_spotify

  attribute :track_count, &:track_count

  attribute :last_synced_at do |playlist|
    playlist.last_synced_at&.iso8601
  end

  attribute :is_liked_songs, &:liked_songs?

  attribute :smart_playlist_id do |playlist|
    playlist.smart_playlist_as_target&.id
  end

  attribute :is_smart, &:smart?
end
