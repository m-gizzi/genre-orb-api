# frozen_string_literal: true

module Genres
  class Filter < Filters::Base
    SORT_NODES = {
      "name" => -> { Genre.arel_table[:name] },
      "track_count" => -> { Arel.sql("library_track_count") },
    }.freeze

    DEFAULT_SORT = "name"
    SORT_NULLS = :none

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
      ActiveRecord::Base.sanitize_sql_array(
        [
          "INNER JOIN (" \
          "SELECT track_genres.genre_id, COUNT(DISTINCT track_genres.track_id) AS library_track_count " \
          "FROM track_genres " \
          "INNER JOIN playlist_version_tracks ON playlist_version_tracks.track_id = track_genres.track_id " \
          "INNER JOIN playlist_versions ON playlist_versions.id = playlist_version_tracks.playlist_version_id " \
          "INNER JOIN playlists ON playlists.id = playlist_versions.playlist_id " \
          "WHERE playlists.user_id = ? AND playlist_versions.id = playlists.current_version_id " \
          "GROUP BY track_genres.genre_id" \
          ") library_track_counts ON library_track_counts.genre_id = genres.id",
          user.id,
        ],
      )
    end
  end
end
