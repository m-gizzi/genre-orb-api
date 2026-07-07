# frozen_string_literal: true

class AddSnapshotIdToPlaylistVersions < ActiveRecord::Migration[8.1]
  def change
    add_column :playlist_versions, :snapshot_id, :string
  end
end
