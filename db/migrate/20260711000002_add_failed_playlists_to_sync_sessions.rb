# frozen_string_literal: true

class AddFailedPlaylistsToSyncSessions < ActiveRecord::Migration[8.1]
  def change
    add_column :sync_sessions, :failed_playlists, :integer, default: 0, null: false
  end
end
