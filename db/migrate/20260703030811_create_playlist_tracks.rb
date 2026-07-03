# frozen_string_literal: true

class CreatePlaylistTracks < ActiveRecord::Migration[8.1]
  def change
    create_table :playlist_tracks do |t|
      t.references :playlist, null: false, foreign_key: true
      t.references :track, null: false, foreign_key: true
      t.integer :position, null: false
      t.datetime :added_at

      t.timestamps
    end

    add_index :playlist_tracks, [:playlist_id, :track_id], unique: true
    add_index :playlist_tracks, [:playlist_id, :position]
    add_index :playlist_tracks, :added_at
  end
end
