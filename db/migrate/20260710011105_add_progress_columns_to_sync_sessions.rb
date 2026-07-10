class AddProgressColumnsToSyncSessions < ActiveRecord::Migration[8.1]
  def change
    add_column :sync_sessions, :total_playlists, :integer, default: 0, null: false
    add_column :sync_sessions, :completed_playlists, :integer, default: 0, null: false
    add_column :sync_sessions, :skipped_playlists, :integer, default: 0, null: false
  end
end
