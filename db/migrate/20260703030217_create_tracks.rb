# frozen_string_literal: true

class CreateTracks < ActiveRecord::Migration[8.1]
  def change
    create_table :tracks do |t|
      t.string :title, null: false
      t.references :album, null: false, foreign_key: true
      t.string :spotify_id, null: false
      t.integer :duration_ms
      t.integer :track_number
      t.boolean :explicit, default: false, null: false
      t.string :preview_url
      t.integer :popularity
      t.jsonb :metadata_overrides, default: {}

      t.timestamps
    end

    add_index :tracks, :spotify_id, unique: true
    add_index :tracks, :title
    add_index :tracks, :popularity
    add_index :tracks, :explicit
  end
end
