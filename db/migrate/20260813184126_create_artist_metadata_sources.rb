# frozen_string_literal: true

class CreateArtistMetadataSources < ActiveRecord::Migration[8.1]
  def change
    create_table :artist_metadata_sources do |t|
      t.references :artist, null: false, foreign_key: true
      t.integer :source, null: false
      t.integer :state, null: false, default: 0
      t.string :external_id
      t.string :external_url
      t.datetime :retry_after
      t.datetime :fetched_at
      t.datetime :attempted_at
      t.integer :failure_count, null: false, default: 0
      t.string :last_error

      t.timestamps
    end

    add_index :artist_metadata_sources, %i[artist_id source], unique: true
    add_index :artist_metadata_sources, %i[source retry_after]
    add_index :artist_metadata_sources, %i[source state]
  end
end
