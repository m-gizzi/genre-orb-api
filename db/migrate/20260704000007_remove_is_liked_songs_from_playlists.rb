# frozen_string_literal: true

class RemoveIsLikedSongsFromPlaylists < ActiveRecord::Migration[8.1]
  def up
    safety_assured do
      execute <<-SQL.squish
        UPDATE playlists
        SET type = 'LikedSongsPlaylist'
        WHERE is_liked_songs = true
      SQL

      remove_index :playlists, %i[user_id is_liked_songs]
      remove_column :playlists, :is_liked_songs
    end
  end

  def down
    add_column :playlists, :is_liked_songs, :boolean, default: false, null: false

    execute <<-SQL.squish
      UPDATE playlists
      SET is_liked_songs = true
      WHERE type = 'LikedSongsPlaylist'
    SQL

    add_index :playlists, %i[user_id is_liked_songs]
  end
end
