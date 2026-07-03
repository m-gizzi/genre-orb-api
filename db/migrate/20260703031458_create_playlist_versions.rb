# frozen_string_literal: true

class CreatePlaylistVersions < ActiveRecord::Migration[8.1]
  def change
    create_table :playlist_versions do |t|
      t.references :playlist, null: false, foreign_key: true
      t.integer :version_number, null: false
      t.bigint :track_ids, array: true, default: []
      t.integer :track_count, null: false, default: 0

      t.timestamps
    end

    add_index :playlist_versions, [:playlist_id, :version_number], unique: true
    add_index :playlist_versions, :track_ids, using: :gin
  end
end
