# frozen_string_literal: true

class SmartPlaylistSerializer
  include Alba::Resource

  attributes :id, :is_enabled, :rules, :match_count

  attribute :name, &:name

  attribute :is_ready, &:ready?

  attribute :source_count do |smart_playlist|
    smart_playlist.source_playlists.size
  end

  attribute :target_playlist do |smart_playlist|
    PlaylistSerializer.new(smart_playlist.target_playlist).serializable_hash
  end

  attribute :last_evaluated_at do |smart_playlist|
    smart_playlist.last_evaluated_at&.iso8601
  end

  attribute :last_pushed_at do |smart_playlist|
    smart_playlist.last_pushed_at&.iso8601
  end
end
