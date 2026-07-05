# frozen_string_literal: true

class PlaylistSerializer
  include Alba::Resource

  attributes :id, :name, :spotify_id, :is_public,
             :sync_enabled, :available_on_spotify

  attribute :track_count do |playlist|
    playlist.track_count
  end

  attribute :last_synced_at do |playlist|
    playlist.last_synced_at&.iso8601
  end

  attribute :is_liked_songs do |playlist|
    playlist.liked_songs?
  end
end
