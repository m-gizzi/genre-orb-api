# frozen_string_literal: true

class AddTrackFilteringIndexes < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_index :tracks, :duration_ms, algorithm: :concurrently

    add_index :tracks, :title,
              using: :gin, opclass: :gin_trgm_ops,
              name: "index_tracks_on_title_trgm",
              algorithm: :concurrently

    add_index :artists, :name,
              using: :gin, opclass: :gin_trgm_ops,
              name: "index_artists_on_name_trgm",
              algorithm: :concurrently

    add_index :albums, :title,
              using: :gin, opclass: :gin_trgm_ops,
              name: "index_albums_on_title_trgm",
              algorithm: :concurrently
  end
end
