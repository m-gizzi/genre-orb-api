# frozen_string_literal: true

class AddSourceToTrackGenresUniqueConstraint < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    add_index :track_genres, %i[track_id genre_id source],
              unique: true,
              name: "index_track_genres_on_track_id_genre_id_source",
              algorithm: :concurrently
    remove_index :track_genres, name: "index_track_genres_on_track_id_and_genre_id", algorithm: :concurrently
  end

  def down
    add_index :track_genres, %i[track_id genre_id],
              unique: true,
              name: "index_track_genres_on_track_id_and_genre_id",
              algorithm: :concurrently
    remove_index :track_genres, name: "index_track_genres_on_track_id_genre_id_source", algorithm: :concurrently
  end
end
