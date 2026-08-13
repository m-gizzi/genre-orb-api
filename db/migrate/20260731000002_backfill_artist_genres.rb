# frozen_string_literal: true

class BackfillArtistGenres < ActiveRecord::Migration[8.1]
  # Deliberately self-contained SQL. This used to call Spotify::ArtistGenrePropagator
  # and reference the ArtistGenre model, both of which have since moved on — a
  # migration has to keep running against the schema as it stood here, so it replays
  # the normalization (downcase, trim, collapse whitespace) inline rather than
  # borrowing today's implementation of it.
  NORMALIZED_NAME = "regexp_replace(btrim(lower(genre_name)), '[[:space:]]+', ' ', 'g')"

  # strong_migrations cannot see inside `execute`. Both statements below are inserts
  # against tables created two migrations earlier, guarded by ON CONFLICT.
  def up
    safety_assured do
      insert_genres
      insert_artist_genres
    end
  end

  def down
    safety_assured { execute("DELETE FROM artist_genres") }
  end

  private

  def insert_genres
    execute(<<~SQL)
      INSERT INTO genres (name, created_at, updated_at)
      SELECT DISTINCT #{NORMALIZED_NAME}, NOW(), NOW()
      FROM artists
      CROSS JOIN LATERAL jsonb_array_elements_text(artists.metadata -> 'genres') AS genre_name
      WHERE jsonb_typeof(artists.metadata -> 'genres') = 'array'
        AND btrim(genre_name) <> ''
      ON CONFLICT (name) DO NOTHING
    SQL
  end

  def insert_artist_genres
    execute(<<~SQL)
      INSERT INTO artist_genres (artist_id, genre_id, created_at, updated_at)
      SELECT DISTINCT artists.id, genres.id, NOW(), NOW()
      FROM artists
      CROSS JOIN LATERAL jsonb_array_elements_text(artists.metadata -> 'genres') AS genre_name
      INNER JOIN genres ON genres.name = #{NORMALIZED_NAME}
      WHERE jsonb_typeof(artists.metadata -> 'genres') = 'array'
      ORDER BY artists.id, genres.id
      ON CONFLICT DO NOTHING
    SQL
  end
end
