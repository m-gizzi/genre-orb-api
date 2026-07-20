# frozen_string_literal: true

module Genres
  class Filter < Filters::Base
    SORT_NODES = {
      "name" => -> { Genre.arel_table[:name] },
      "track_count" => -> { Arel.sql("library_track_count") },
    }.freeze

    DEFAULT_SORT = "name"
    SORT_NULLS = :none

    TRACK_COUNTS_JOIN = <<~SQL.squish
      INNER JOIN (
        SELECT track_genres.genre_id, COUNT(DISTINCT track_genres.track_id) AS library_track_count
        FROM track_genres
        WHERE track_genres.track_id IN (
          SELECT playlist_version_tracks.track_id FROM playlist_version_tracks
          WHERE playlist_version_tracks.playlist_version_id IN (
            SELECT playlists.current_version_id FROM playlists
            WHERE playlists.user_id = ? AND playlists.current_version_id IS NOT NULL
          )
        )
        GROUP BY track_genres.genre_id
      ) library_track_counts ON library_track_counts.genre_id = genres.id
    SQL

    def call
      relation = search(base_relation, Genre.arel_table[:name])
      relation.order(*sort.terms)
    end

    private

    def base_relation
      return user.library_genres unless sort.key == "track_count"

      Genre.joins(library_track_counts_join).select("genres.*", "library_track_count")
    end

    def library_track_counts_join
      ActiveRecord::Base.sanitize_sql_array([TRACK_COUNTS_JOIN, user.id])
    end
  end
end
