# frozen_string_literal: true

module Albums
  class Filter < Filters::Base
    include Filters::GenreScopable

    DERIVED_POPULARITY = "(SELECT AVG(tracks.popularity) FROM tracks WHERE tracks.album_id = albums.id)"

    SORT_NODES = {
      "title" => -> { Album.arel_table[:title] },
      "release_year" => -> { Album.arel_table[:release_year] },
      "popularity" => -> { Arel.sql("derived_popularity") },
    }.freeze

    DEFAULT_SORT = "title"

    def call
      relation = user.library_albums.includes(:artists)
      relation = search(relation, "albums.title")
      relation = filter_genre(relation)
      relation = filter_artist(relation)
      relation = filter_year(relation)
      relation = relation.select("albums.*", "#{DERIVED_POPULARITY} AS derived_popularity") if sort.key == "popularity"
      relation.order(*sort.terms)
    end

    private

    def filter_genre(relation)
      return relation if params[:genre].blank?

      album_ids = Track.where(id: genre_track_ids).where.not(album_id: nil).select(:album_id)
      relation.where(id: album_ids)
    end

    def filter_artist(relation)
      value = params[:artist]
      return relation if value.blank?

      relation.where(id: artist_album_ids(value))
    end

    def artist_album_ids(value)
      scope = if numeric?(value)
                AlbumArtist.where(artist_id: value)
              else
                AlbumArtist.joins(:artist).where("artists.name ILIKE ?", contains(value))
              end
      scope.select(:album_id)
    end

    def filter_year(relation)
      range = Filters::Range.bounded(params[:year_min], params[:year_max])
      range ? relation.where(albums: { release_year: range }) : relation
    end
  end
end
