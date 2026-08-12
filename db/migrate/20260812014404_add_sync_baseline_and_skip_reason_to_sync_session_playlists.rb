# frozen_string_literal: true

class AddSyncBaselineAndSkipReasonToSyncSessionPlaylists < ActiveRecord::Migration[8.1]
  def change
    add_foreign_key :push_sessions, :playlist_versions, column: :baseline_version_id, validate: false
    add_foreign_key :sync_session_playlists, :playlist_versions, column: :baseline_version_id, validate: false
  end
end
