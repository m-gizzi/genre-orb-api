# frozen_string_literal: true

class CreateSyncSessions < ActiveRecord::Migration[8.1]
  def change
    create_table :sync_sessions do |t|
      t.references :user, null: false, foreign_key: true
      t.integer :status, default: 0, null: false
      t.datetime :started_at
      t.datetime :completed_at
      t.string :error_message
      t.string :pause_reason
      t.datetime :resume_at

      t.timestamps
    end

    add_index :sync_sessions, :status
    add_index :sync_sessions, %i[user_id status], name: "idx_sync_sessions_user_status"
  end
end
