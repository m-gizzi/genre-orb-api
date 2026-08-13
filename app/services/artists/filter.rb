# frozen_string_literal: true

module Artists
  class Filter < Filters::Base
    POPULARITY_SORT = <<~SQL.squish
      CASE WHEN artists.metadata->>'popularity' ~ '^-?[0-9]+$'
        THEN (artists.metadata->>'popularity')::int END
    SQL

    FOLLOWERS_SORT = <<~SQL.squish
      CASE WHEN artists.metadata->>'followers' ~ '^-?[0-9]+$'
        THEN (artists.metadata->>'followers')::int END
    SQL

    sorts(
      {
        "name" => -> { Artist.arel_table[:name] },
        "popularity" => -> { Arel.sql(POPULARITY_SORT) },
        "followers" => -> { Arel.sql(FOLLOWERS_SORT) },
      },
      default: "name",
    )

    def call
      Artist.where(id: filtered_ids).includes(artist_genres: :genre).order(*sort.terms)
    end

    private

    def filtered_ids
      relation = user.library_artists
      relation = search(relation, Artist.arel_table[:name])
      relation = filter_genre(relation)
      relation.reselect("artists.id")
    end

    def filter_genre(relation)
      value = params[:genre]
      return relation if value.blank?

      relation.where(id: ArtistGenre.where(genre_id: genre_ids(value)).select(:artist_id))
    end

    def genre_ids(value)
      return [value] if numeric?(value)

      Genre.where(name: Genre.normalize_name(value)).select(:id)
    end
  end
end
