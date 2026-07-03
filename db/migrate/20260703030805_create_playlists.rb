# frozen_string_literal: true

class CreatePlaylists < ActiveRecord::Migration[8.1]
  def change
    create_table :playlists do |t|
      t.references :user, null: false, foreign_key: true
      t.string :name, null: false
      t.string :spotify_id
      t.string :snapshot_id
      t.boolean :is_liked_songs, default: false, null: false
      t.integer :track_count, default: 0, null: false
      t.boolean :is_public, default: false, null: false

      t.timestamps
    end

    add_index :playlists, :spotify_id, unique: true, where: "spotify_id IS NOT NULL"
    add_index :playlists, [:user_id, :is_liked_songs]
    add_index :playlists, :snapshot_id
  end
end
