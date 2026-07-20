# frozen_string_literal: true

module Artists
  class Filter < Filters::Base
    include Filters::GenreScopable

    SORT_NODES = {
      "name" => -> { Artist.arel_table[:name] },
      "popularity" => -> { Arel.sql("(artists.metadata->>'popularity')::int") },
      "followers" => -> { Arel.sql("(artists.metadata->>'followers')::int") },
    }.freeze

    DEFAULT_SORT = "name"

    def call
      Artist.where(id: filtered_ids).includes(:genres).order(*sort.terms)
    end

    private

    def filtered_ids
      relation = user.library_artists
      relation = search(relation, Artist.arel_table[:name])
      relation = filter_genre(relation)
      relation.reselect("artists.id")
    end

    def filter_genre(relation)
      return relation if params[:genre].blank?

      artist_ids = TrackArtist.where(track_id: genre_track_ids).select(:artist_id)
      relation.where(id: artist_ids)
    end
  end
end
