# frozen_string_literal: true

class AllowGlobalArtistMetadataSessions < ActiveRecord::Migration[8.1]
  def up
    change_column_null :artist_metadata_sessions, :user_id, true

    safety_assured do
      execute <<~SQL.squish
        CREATE UNIQUE INDEX idx_unique_active_global_artist_metadata_session
          ON artist_metadata_sessions ((user_id IS NULL))
          WHERE user_id IS NULL AND status IN (0, 1)
      SQL
    end
  end

  def down
    safety_assured { execute "DROP INDEX IF EXISTS idx_unique_active_global_artist_metadata_session" }
    change_column_null :artist_metadata_sessions, :user_id, false
  end
end
