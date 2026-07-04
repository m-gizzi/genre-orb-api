# frozen_string_literal: true

class AddSyncFieldsToPlaylists < ActiveRecord::Migration[8.1]
  def change
    safety_assured do
      add_reference :playlists, :current_version, foreign_key: { to_table: :playlist_versions }
      add_column :playlists, :sync_enabled, :boolean, default: false, null: false
      add_column :playlists, :last_synced_at, :datetime
      add_column :playlists, :available_on_spotify, :boolean, default: true, null: false
      add_column :playlists, :type, :string

      add_index :playlists, :sync_enabled
      add_index :playlists, :type
    end
  end
end
