# frozen_string_literal: true

class AddPushPlanPinningToPushSessions < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_reference :push_sessions, :baseline_version, index: { algorithm: :concurrently }
    add_column :push_sessions, :add_phase_started_at, :datetime

    add_reference :sync_session_playlists, :baseline_version, index: { algorithm: :concurrently }
    add_column :sync_session_playlists, :skip_reason, :integer
  end
end
