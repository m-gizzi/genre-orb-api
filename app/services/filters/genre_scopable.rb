# frozen_string_literal: true

module Filters
  module GenreScopable
    private

    def genre_track_ids
      value = params[:genre]
      rows = effective_genres.tracks.where(track_id: user.library_tracks.select(:id))

      if numeric?(value)
        rows.where(genre_id: value)
      else
        rows.joins(:genre).where(genres: { name: Genre.normalize_name(value) })
      end.select(:track_id)
    end
  end
end
