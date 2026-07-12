# frozen_string_literal: true

module Tracks
  class Filter
    SORT_COLUMNS = {
      "title" => "tracks.title",
      "popularity" => "tracks.popularity",
      "duration" => "tracks.duration_ms",
      "year" => "albums.release_year",
    }.freeze

    DEFAULT_SORT = "title"

    def initialize(scope, params)
      @scope = scope
      @params = params
    end

    def call
      relation = Track.where(id: filtered_ids).with_catalog_associations
      relation = relation.references(:album) if sort_column == SORT_COLUMNS["year"]
      relation.order(order_clause)
    end

    private

    attr_reader :params

    def filtered_ids
      relation = @scope
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
      value = params[:genre]
      return relation if value.blank?

      if numeric?(value)
        relation.joins(:track_genres).where(track_genres: { genre_id: value })
      else
        relation.joins(track_genres: :genre)
                .where(genres: { name: Genre.normalize_name(value) })
      end
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
      value = params[:album_id]
      return relation if value.blank?

      relation.where(tracks: { album_id: value })
    end

    def filter_year(relation)
      exact = params[:year]
      minimum = params[:year_min]
      maximum = params[:year_max]
      return relation if exact.blank? && minimum.blank? && maximum.blank?

      relation = relation.joins(:album)
      relation = relation.where(albums: { release_year: exact }) if exact.present?
      relation = relation.where("albums.release_year >= ?", minimum) if minimum.present?
      relation = relation.where("albums.release_year <= ?", maximum) if maximum.present?
      relation
    end

    def filter_duration(relation)
      minimum = params[:duration_min]
      maximum = params[:duration_max]
      relation = relation.where("tracks.duration_ms >= ?", minimum) if minimum.present?
      relation = relation.where("tracks.duration_ms <= ?", maximum) if maximum.present?
      relation
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

    def order_clause
      Arel.sql("#{sort_column} #{direction} NULLS LAST, tracks.id ASC")
    end

    def sort_column
      SORT_COLUMNS.fetch(params[:sort].to_s, SORT_COLUMNS[DEFAULT_SORT])
    end

    def direction
      params[:order].to_s.casecmp("desc").zero? ? "DESC" : "ASC"
    end

    def numeric?(value)
      value.to_s.match?(/\A\d+\z/)
    end

    def contains(value)
      "%#{ActiveRecord::Base.sanitize_sql_like(value.to_s)}%"
    end
  end
end
