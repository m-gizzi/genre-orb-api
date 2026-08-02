# frozen_string_literal: true

class NormalizeSmartPlaylists < ActiveRecord::Migration[8.1]
  def up
    safety_assured do
      execute "DELETE FROM smart_playlists WHERE target_playlist_id IS NULL"

      change_column_null :smart_playlists, :target_playlist_id, false
      remove_index :smart_playlists, column: :target_playlist_id
      add_index :smart_playlists, :target_playlist_id, unique: true

      remove_foreign_key :smart_playlists, :users
      remove_index :smart_playlists, column: %i[user_id name], unique: true
      remove_index :smart_playlists, column: :user_id
      remove_column :smart_playlists, :user_id
      remove_column :smart_playlists, :name
    end
  end

  def down
    add_column :smart_playlists, :name, :string
    add_column :smart_playlists, :user_id, :bigint

    execute <<~SQL.squish
      UPDATE smart_playlists
      SET user_id = playlists.user_id, name = playlists.name
      FROM playlists
      WHERE playlists.id = smart_playlists.target_playlist_id
    SQL

    change_column_null :smart_playlists, :name, false
    change_column_null :smart_playlists, :user_id, false
    add_index :smart_playlists, :user_id
    add_index :smart_playlists, %i[user_id name], unique: true
    add_foreign_key :smart_playlists, :users

    remove_index :smart_playlists, column: :target_playlist_id, unique: true
    add_index :smart_playlists, :target_playlist_id
    change_column_null :smart_playlists, :target_playlist_id, true
  end
end
