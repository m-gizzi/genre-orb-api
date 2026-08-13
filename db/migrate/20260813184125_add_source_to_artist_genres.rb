# frozen_string_literal: true

class AddSourceToArtistGenres < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    add_column :artist_genres, :source, :integer, null: false, default: 0
    add_column :artist_genres, :confidence, :float, null: false, default: 1.0

    add_index :artist_genres, :source, algorithm: :concurrently
    add_index :artist_genres, %i[artist_id genre_id source],
              unique: true,
              name: "index_artist_genres_on_artist_id_genre_id_source",
              algorithm: :concurrently
    remove_index :artist_genres,
                 name: "index_artist_genres_on_artist_id_and_genre_id",
                 algorithm: :concurrently
  end

  def down
    # Two sources agreeing on a genre collapse to one row, so the narrower index
    # can only be restored after the duplicates are gone.
    execute(<<~SQL.squish)
      DELETE FROM artist_genres WHERE id NOT IN (
        SELECT MIN(id) FROM artist_genres GROUP BY artist_id, genre_id
      )
    SQL

    add_index :artist_genres, %i[artist_id genre_id],
              unique: true,
              name: "index_artist_genres_on_artist_id_and_genre_id",
              algorithm: :concurrently
    remove_index :artist_genres, name: "index_artist_genres_on_artist_id_genre_id_source", algorithm: :concurrently
    remove_index :artist_genres, :source, algorithm: :concurrently

    remove_column :artist_genres, :confidence
    remove_column :artist_genres, :source
  end
end
