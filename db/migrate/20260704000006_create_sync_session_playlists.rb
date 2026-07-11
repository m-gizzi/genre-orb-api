# frozen_string_literal: true

class CreateSyncSessionPlaylists < ActiveRecord::Migration[8.1]
  def change
    create_table :sync_session_playlists do |t|
      t.references :sync_session, null: false, foreign_key: true
      t.references :playlist, null: false, foreign_key: true
      t.references :playlist_version, foreign_key: true
      t.integer :status, default: 0, null: false
      t.integer :total_pages, default: 0
      t.integer :completed_pages, default: 0
      t.string :error_message
      t.datetime :started_at
      t.datetime :completed_at

      t.timestamps
    end

    add_index :sync_session_playlists, %i[sync_session_id playlist_id],
              unique: true,
              name: "idx_sync_session_playlists_unique"
    add_index :sync_session_playlists, :status
  end
end
