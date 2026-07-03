# frozen_string_literal: true

class CreateTrackGenres < ActiveRecord::Migration[8.1]
  def change
    create_table :track_genres do |t|
      t.references :track, null: false, foreign_key: true
      t.references :genre, null: false, foreign_key: true
      t.float :confidence, default: 1.0, null: false

      t.timestamps
    end

    add_index :track_genres, [:track_id, :genre_id], unique: true
    add_index :track_genres, :confidence
  end
end
