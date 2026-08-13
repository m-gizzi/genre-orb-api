# frozen_string_literal: true

class ValidateScheduledRunForeignKeys < ActiveRecord::Migration[8.1]
  def change
    validate_foreign_key :sync_sessions, :scheduled_runs
    validate_foreign_key :artist_metadata_sessions, :scheduled_runs
    validate_foreign_key :push_sessions, :scheduled_runs
  end
end
