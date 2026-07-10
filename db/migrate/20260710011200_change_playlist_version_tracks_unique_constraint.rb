# frozen_string_literal: true

class ChangePlaylistVersionTracksUniqueConstraint < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    # Remove the unique constraint on (playlist_version_id, track_id) to allow duplicate tracks
    remove_index :playlist_version_tracks, name: "idx_playlist_version_tracks_unique", algorithm: :concurrently

    # Add a non-unique index on track_id for query performance
    add_index :playlist_version_tracks, %i[playlist_version_id track_id],
              name: "idx_playlist_version_tracks_lookup",
              algorithm: :concurrently

    remove_index :playlist_version_tracks, name: "idx_playlist_version_tracks_position", algorithm: :concurrently
    add_index :playlist_version_tracks, %i[playlist_version_id position],
              unique: true,
              name: "idx_playlist_version_tracks_position",
              algorithm: :concurrently
  end
end
