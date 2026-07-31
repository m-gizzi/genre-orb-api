# frozen_string_literal: true

class CreateArtistGenres < ActiveRecord::Migration[8.1]
  def change
    create_table :artist_genres do |t|
      t.references :artist, null: false, foreign_key: true
      t.references :genre, null: false, foreign_key: true
      t.timestamps
    end

    add_index :artist_genres, %i[artist_id genre_id], unique: true
  end
end
