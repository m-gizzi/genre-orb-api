# frozen_string_literal: true

class ReplacePlaylistTracksWithVersionTracks < ActiveRecord::Migration[8.1]
  def up
    drop_table :playlist_tracks

    create_table :playlist_version_tracks do |t|
      t.references :playlist_version, null: false, foreign_key: true
      t.references :track, null: false, foreign_key: true
      t.integer :position, null: false
      t.datetime :added_at

      t.timestamps
    end

    add_index :playlist_version_tracks, %i[playlist_version_id track_id],
              unique: true,
              name: "idx_playlist_version_tracks_unique"
    add_index :playlist_version_tracks, %i[playlist_version_id position],
              name: "idx_playlist_version_tracks_position"
  end

  def down
    drop_table :playlist_version_tracks

    create_table :playlist_tracks do |t|
      t.references :playlist, null: false, foreign_key: true
      t.references :track, null: false, foreign_key: true
      t.integer :position, null: false
      t.datetime :added_at

      t.timestamps
    end

    add_index :playlist_tracks, %i[playlist_id track_id], unique: true
    add_index :playlist_tracks, %i[playlist_id position]
    add_index :playlist_tracks, :added_at
  end
end
