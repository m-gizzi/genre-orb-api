# frozen_string_literal: true

class AddUniqueActiveSessionIndexes < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  # Enforce at most one in-flight (pending/running) session per user, closing the
  # check-then-create race between concurrent sync requests. Status enums: pending=0, running=1.
  def change
    add_index :sync_sessions, :user_id,
              unique: true,
              where: "status IN (0, 1)",
              name: "idx_unique_active_sync_session_per_user",
              algorithm: :concurrently

    add_index :artist_metadata_sessions, :user_id,
              unique: true,
              where: "status IN (0, 1)",
              name: "idx_unique_active_artist_metadata_session_per_user",
              algorithm: :concurrently
  end
end
