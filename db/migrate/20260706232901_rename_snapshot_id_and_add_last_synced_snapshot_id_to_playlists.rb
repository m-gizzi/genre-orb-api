# frozen_string_literal: true

class RenameSnapshotIdAndAddLastSyncedSnapshotIdToPlaylists < ActiveRecord::Migration[8.1]
  def change
    safety_assured do
      rename_column :playlists, :snapshot_id, :last_seen_snapshot_id
      add_column :playlists, :last_synced_snapshot_id, :string
      add_index :playlists, :last_synced_snapshot_id
    end
  end
end
