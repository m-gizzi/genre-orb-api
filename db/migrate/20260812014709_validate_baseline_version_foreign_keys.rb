# frozen_string_literal: true

class ValidateBaselineVersionForeignKeys < ActiveRecord::Migration[8.1]
  def change
    validate_foreign_key :push_sessions, column: :baseline_version_id
    validate_foreign_key :sync_session_playlists, column: :baseline_version_id
  end
end
