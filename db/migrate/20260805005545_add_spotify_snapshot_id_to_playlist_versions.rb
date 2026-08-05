# frozen_string_literal: true

class AddSpotifySnapshotIdToPlaylistVersions < ActiveRecord::Migration[8.1]
  def change
    add_column :playlist_versions, :spotify_snapshot_id, :string
  end
end
