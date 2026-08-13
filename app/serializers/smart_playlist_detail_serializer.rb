# frozen_string_literal: true

class SmartPlaylistDetailSerializer < SmartPlaylistSerializer
  attribute :source_playlists do |smart_playlist|
    PlaylistSummarySerializer.new(smart_playlist.source_playlists).serializable_hash
  end

  attribute :rule_playlists do |smart_playlist|
    PlaylistSummarySerializer.new(smart_playlist.rule_playlists).serializable_hash
  end
end
