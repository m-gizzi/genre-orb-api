# frozen_string_literal: true

module Genres
  class Filter < Filters::Base
    TRACK_COUNTS_SELECT = "track_genres.genre_id, COUNT(DISTINCT track_genres.track_id) AS library_track_count"

    sorts(
      {
        "name" => -> { Genre.arel_table[:name] },
        "track_count" => -> { Arel.sql("library_track_counts.library_track_count") },
      },
      default: "name",
      nulls: :none,
    )

    def call
      relation = search(base_relation, Genre.arel_table[:name])
      relation.order(*sort.terms)
    end

    private

    def base_relation
      return user.library_genres unless sort.key == "track_count"

      Genre.joins(track_counts_join)
    end

    def track_counts
      TrackGenre.where(track_id: user.library_tracks.select(:id))
                .group(:genre_id)
                .select(TRACK_COUNTS_SELECT)
    end

    def track_counts_join
      "INNER JOIN (#{track_counts.to_sql}) library_track_counts " \
        "ON library_track_counts.genre_id = genres.id"
    end
  end
end
