# frozen_string_literal: true

class RemoveSnapshotIdFromPlaylistVersions < ActiveRecord::Migration[8.1]
  def change
    safety_assured { remove_column :playlist_versions, :snapshot_id, :string }
  end
end
