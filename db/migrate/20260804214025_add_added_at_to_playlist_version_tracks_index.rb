# frozen_string_literal: true

class AddAddedAtToPlaylistVersionTracksIndex < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_index :playlist_version_tracks,
              %i[playlist_version_id track_id added_at],
              name: "idx_playlist_version_tracks_added_at",
              algorithm: :concurrently

    remove_index :playlist_version_tracks,
                 column: %i[playlist_version_id track_id],
                 name: "idx_playlist_version_tracks_lookup",
                 algorithm: :concurrently
  end
end
