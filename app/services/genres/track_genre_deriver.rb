# frozen_string_literal: true

module Genres
  # Projects artist_genres down onto the artists' tracks, carrying each row's source
  # and confidence through. Deliberately source-agnostic: re-deriving one artist
  # refreshes every source's rows for their tracks, which makes it self-healing.
  class TrackGenreDeriver
    # DISTINCT ON is load-bearing. A track credited to two artists that both carry the
    # same genre from the same source yields two candidate rows for one conflict
    # target, and Postgres refuses to affect a row twice in one statement. The plain
    # DISTINCT this replaced was immune only because it paired with DO NOTHING.
    # Ordering by confidence DESC keeps the stronger attribution.
    TEMPLATE = <<~SQL.squish
      INSERT INTO track_genres (track_id, genre_id, source, confidence, created_at, updated_at)
      SELECT DISTINCT ON (track_artists.track_id, artist_genres.genre_id, artist_genres.source)
             track_artists.track_id,
             artist_genres.genre_id,
             artist_genres.source,
             artist_genres.confidence,
             NOW(),
             NOW()
      FROM track_artists
      INNER JOIN artist_genres ON artist_genres.artist_id = track_artists.artist_id
      WHERE track_artists.%<filter>s IN (?)
      ORDER BY track_artists.track_id,
               artist_genres.genre_id,
               artist_genres.source,
               artist_genres.confidence DESC
      ON CONFLICT (track_id, genre_id, source) DO UPDATE
        SET confidence = EXCLUDED.confidence, updated_at = NOW()
        WHERE track_genres.confidence IS DISTINCT FROM EXCLUDED.confidence
    SQL

    BY_ARTIST = format(TEMPLATE, filter: "artist_id").freeze
    BY_TRACK = format(TEMPLATE, filter: "track_id").freeze

    def by_artist(artist_ids)
      derive(BY_ARTIST, artist_ids)
    end

    def by_track(track_ids)
      derive(BY_TRACK, track_ids)
    end

    private

    def derive(statement, ids)
      ids = Array(ids).compact.uniq
      return if ids.empty?

      sql = ActiveRecord::Base.sanitize_sql_array([statement, ids])
      TrackGenre.connection.execute(sql)
    end
  end
end
