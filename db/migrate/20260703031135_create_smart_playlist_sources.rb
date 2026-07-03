# frozen_string_literal: true

class CreateSmartPlaylistSources < ActiveRecord::Migration[8.1]
  def change
    create_table :smart_playlist_sources do |t|
      t.references :smart_playlist, null: false, foreign_key: true
      t.references :playlist, null: false, foreign_key: true

      t.timestamps
    end

    add_index :smart_playlist_sources, [:smart_playlist_id, :playlist_id], unique: true, name: "idx_smart_playlist_sources_unique"
  end
end
