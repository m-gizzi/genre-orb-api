# frozen_string_literal: true

class SyncSessionPlaylistSerializer
  include Alba::Resource

  attributes :status, :error_message

  attribute :playlist_id, &:playlist_id

  attribute :playlist_name do |playlist_session|
    playlist_session.playlist.name
  end

  attribute :page_progress, &:page_progress
end
