# frozen_string_literal: true

module Tracks
  class Filter < Filters::Base
    include Filters::GenreScopable

    SORT_NODES = {
      "title" => -> { Track.arel_table[:title] },
      "popularity" => -> { Track.arel_table[:popularity] },
      "duration" => -> { Track.arel_table[:duration_ms] },
      "year" => -> { Album.arel_table[:release_year] },
      "album" => -> { Album.arel_table[:title] },
      "artist" => lambda {
        Arel.sql(
          "(SELECT MIN(artists.name) FROM artists " \
          "INNER JOIN track_artists ON track_artists.artist_id = artists.id " \
          "WHERE track_artists.track_id = tracks.id)",
        )
      },
    }.freeze

    ALBUM_SORTS = %w[year album].freeze

    DEFAULT_SORT = "title"
    SORT_NULLS = :last

    def call
      relation = Track.where(id: filtered_ids).with_catalog_associations
      relation = relation.references(:album) if ALBUM_SORTS.include?(sort.key)
      relation.order(*order_terms)
    end

    private

    def filtered_ids
      relation = user.library_tracks
      relation = filter_genre(relation)
      relation = filter_artist(relation)
      relation = filter_album(relation)
      relation = filter_year(relation)
      relation = filter_duration(relation)
      relation = filter_title(relation)
      relation = filter_explicit(relation)
      relation.reselect("tracks.id")
    end

    def filter_genre(relation)
      return relation if params[:genre].blank?

      relation.where(id: genre_track_ids)
    end

    def filter_artist(relation)
      value = params[:artist]
      return relation if value.blank?

      if numeric?(value)
        relation.joins(:track_artists).where(track_artists: { artist_id: value })
      else
        relation.joins(:artists).where("artists.name ILIKE ?", contains(value))
      end
    end

    def filter_album(relation)
      value = params[:album]
      return relation if value.blank?

      if numeric?(value)
        relation.where(tracks: { album_id: value })
      else
        relation.joins(:album).where("albums.title ILIKE ?", contains(value))
      end
    end

    def filter_year(relation)
      return relation unless any_year_param?

      relation = relation.joins(:album)
      relation = relation.where(albums: { release_year: params[:year] }) if params[:year].present?
      apply_range(relation, :albums, :release_year, params[:year_min], params[:year_max])
    end

    def filter_duration(relation)
      apply_range(relation, :tracks, :duration_ms, params[:duration_min], params[:duration_max])
    end

    def any_year_param?
      [params[:year], params[:year_min], params[:year_max]].any?(&:present?)
    end

    def apply_range(relation, table, column, minimum, maximum)
      range = Filters::Range.bounded(minimum, maximum)
      range ? relation.where(table => { column => range }) : relation
    end

    def filter_title(relation)
      value = params[:title]
      return relation if value.blank?

      relation.where("tracks.title ILIKE ?", contains(value))
    end

    def filter_explicit(relation)
      value = params[:explicit]
      return relation if value.nil? || value == ""

      relation.where(tracks: { explicit: ActiveModel::Type::Boolean.new.cast(value) })
    end

    def order_terms
      sort.terms(*secondary_terms, Track.arel_table[:id].asc)
    end

    def secondary_terms
      return [] unless sort.key == "album"

      [Track.arel_table[:track_number].asc.nulls_last]
    end
  end
end
