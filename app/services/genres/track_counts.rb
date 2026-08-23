# frozen_string_literal: true

module Genres
  class TrackCounts
    COUNT_SELECT = "track_genres.genre_id, COUNT(DISTINCT track_genres.track_id) AS track_count"

    def initialize(scope, tracks)
      @scope = scope
      @tracks = tracks
    end

    def join(alias_name)
      "INNER JOIN (#{grouped.select(COUNT_SELECT).to_sql}) #{alias_name} " \
        "ON #{alias_name}.genre_id = genres.id"
    end

    def for_genres(genres)
      grouped.where(genre_id: genres.map(&:id)).distinct.count(:track_id)
    end

    def genre_ids
      grouped.select(:genre_id)
    end

    private

    attr_reader :scope, :tracks

    def grouped
      scope.tracks.where(track_id: tracks.select(:id)).group(:genre_id)
    end
  end
end
