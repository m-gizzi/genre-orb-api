# frozen_string_literal: true

class CreateArtists < ActiveRecord::Migration[8.1]
  def change
    create_table :artists do |t|
      t.string :name, null: false
      t.string :spotify_id, null: false
      t.string :image_url
      t.jsonb :metadata, default: {}

      t.timestamps
    end

    add_index :artists, :spotify_id, unique: true
    add_index :artists, :name
  end
end
