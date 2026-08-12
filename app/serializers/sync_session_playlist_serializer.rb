# frozen_string_literal: true

class SyncSessionPlaylistSerializer
  include Alba::Resource

  attributes :status, :error_message, :playlist_id, :page_progress

  attribute :playlist_name do |playlist_session|
    playlist_session.playlist.name
  end
end
