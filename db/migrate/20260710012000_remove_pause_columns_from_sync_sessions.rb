# frozen_string_literal: true

class RemovePauseColumnsFromSyncSessions < ActiveRecord::Migration[8.1]
  def change
    safety_assured do
      remove_column :sync_sessions, :pause_reason, :string
      remove_column :sync_sessions, :resume_at, :datetime
    end
  end
end
