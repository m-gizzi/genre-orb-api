# frozen_string_literal: true

module Albums
  class Filter < Filters::Base
    include Filters::GenreScopable

    AVERAGE_TRACK_POPULARITY = <<~SQL.squish
      (SELECT AVG(tracks.popularity) FROM tracks WHERE tracks.album_id = albums.id)
    SQL

    sorts(
      {
        "title" => -> { Album.arel_table[:title] },
        "release_year" => -> { Album.arel_table[:release_year] },
        "popularity" => -> { Arel.sql(AVERAGE_TRACK_POPULARITY) },
      },
      default: "title",
    )

    def call
      relation = user.library_albums.includes(:artists)
      relation = search(relation, Album.arel_table[:title])
      relation = filter_genre(relation)
      relation = filter_artist(relation)
      relation = filter_year(relation)
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
