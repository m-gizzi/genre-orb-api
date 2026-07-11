# frozen_string_literal: true

class ChangePlaylistsUniqueIndexToPerUser < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_index :playlists, %i[user_id spotify_id],
              unique: true,
              where: "spotify_id IS NOT NULL",
              name: "idx_playlists_user_spotify_unique",
              algorithm: :concurrently

    remove_index :playlists,
                 name: "index_playlists_on_spotify_id",
                 column: :spotify_id,
                 unique: true,
                 where: "(spotify_id IS NOT NULL)",
                 algorithm: :concurrently

    add_index :playlists, :user_id,
              unique: true,
              where: "type = 'LikedSongsPlaylist'",
              name: "idx_playlists_liked_songs_per_user",
              algorithm: :concurrently
  end
end
