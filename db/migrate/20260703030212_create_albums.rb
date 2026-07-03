# frozen_string_literal: true

class CreateAlbums < ActiveRecord::Migration[8.1]
  def change
    create_table :albums do |t|
      t.string :title, null: false
      t.string :spotify_id, null: false
      t.integer :release_year
      t.string :artwork_url
      t.integer :total_tracks

      t.timestamps
    end

    add_index :albums, :spotify_id, unique: true
    add_index :albums, :release_year
    add_index :albums, :title
  end
end
