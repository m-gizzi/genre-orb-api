# frozen_string_literal: true

class CreateTrackArtists < ActiveRecord::Migration[8.1]
  def change
    create_table :track_artists do |t|
      t.references :track, null: false, foreign_key: true
      t.references :artist, null: false, foreign_key: true

      t.timestamps
    end

    add_index :track_artists, [:track_id, :artist_id], unique: true
  end
end
