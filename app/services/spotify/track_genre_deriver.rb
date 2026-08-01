# frozen_string_literal: true

module Spotify
  class TrackGenreDeriver
    BY_ARTIST = <<~SQL.squish
      INSERT INTO track_genres (track_id, genre_id, source, confidence, created_at, updated_at)
      SELECT DISTINCT track_artists.track_id, artist_genres.genre_id, ?, 1.0, NOW(), NOW()
      FROM track_artists
      INNER JOIN artist_genres ON artist_genres.artist_id = track_artists.artist_id
      WHERE track_artists.artist_id IN (?)
      ORDER BY track_artists.track_id, artist_genres.genre_id
      ON CONFLICT (track_id, genre_id, source) DO NOTHING
    SQL

    BY_TRACK = <<~SQL.squish
      INSERT INTO track_genres (track_id, genre_id, source, confidence, created_at, updated_at)
      SELECT DISTINCT track_artists.track_id, artist_genres.genre_id, ?, 1.0, NOW(), NOW()
      FROM track_artists
      INNER JOIN artist_genres ON artist_genres.artist_id = track_artists.artist_id
      WHERE track_artists.track_id IN (?)
      ORDER BY track_artists.track_id, artist_genres.genre_id
      ON CONFLICT (track_id, genre_id, source) DO NOTHING
    SQL

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

      sql = ActiveRecord::Base.sanitize_sql_array([statement, TrackGenre.sources[:spotify], ids])
      TrackGenre.connection.execute(sql)
    end
  end
end
