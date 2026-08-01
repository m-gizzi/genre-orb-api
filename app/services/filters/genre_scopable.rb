# frozen_string_literal: true

module Filters
  module GenreScopable
    private

    def genre_track_ids
      value = params[:genre]
      relation = user.library_tracks

      if numeric?(value)
        relation.joins(:track_genres).where(track_genres: { genre_id: value })
      else
        relation.joins(track_genres: :genre)
                .where(genres: { name: Genre.normalize_name(value) })
      end.reselect("tracks.id")
    end
  end
end
