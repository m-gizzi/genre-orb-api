# frozen_string_literal: true

class SyncSessionSerializer < SessionSerializer
  attribute :playlists do |session|
    SyncSessionPlaylistSerializer.new(session.sync_session_playlists.sort_by(&:id)).serializable_hash
  end
end
