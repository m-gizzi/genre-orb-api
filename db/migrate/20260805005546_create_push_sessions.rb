# frozen_string_literal: true

class CreatePushSessions < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    create_table :push_sessions do |t|
      t.references :smart_playlist, null: false, foreign_key: true
      t.references :playlist_version, foreign_key: true
      t.integer :status, null: false, default: 0
      t.integer :strategy, null: false, default: 0

      t.integer :total_remove_batches, null: false, default: 0
      t.integer :completed_remove_batches, null: false, default: 0
      t.integer :total_add_batches, null: false, default: 0
      t.integer :completed_add_batches, null: false, default: 0

      t.integer :tracks_added, null: false, default: 0
      t.integer :tracks_removed, null: false, default: 0
      t.integer :match_count, null: false, default: 0
      t.boolean :sampled, null: false, default: false

      t.string :spotify_snapshot_id
      t.string :error_message
      t.datetime :started_at
      t.datetime :completed_at

      t.timestamps
    end

    add_index :push_sessions, :status
    add_index :push_sessions, %i[smart_playlist_id status]

    add_index :push_sessions, :smart_playlist_id,
              unique: true,
              where: "status IN (0, 1)",
              name: "idx_unique_active_push_session_per_smart_playlist",
              algorithm: :concurrently
  end
end
