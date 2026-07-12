# frozen_string_literal: true

module Tracks
  class Filter
    SORT_ATTRIBUTES = {
      "title" => -> { Track.arel_table[:title] },
      "popularity" => -> { Track.arel_table[:popularity] },
      "duration" => -> { Track.arel_table[:duration_ms] },
      "year" => -> { Album.arel_table[:release_year] },
    }.freeze

    DEFAULT_SORT = "title"

    def initialize(scope, params)
      @scope = scope
      @params = params
    end

    def call
      relation = Track.where(id: filtered_ids).with_catalog_associations
      relation = relation.references(:album) if sort_key == "year"
      relation.order(*order_terms)
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
      range = bounded_range(minimum, maximum)
      range ? relation.where(table => { column => range }) : relation
    end

    def bounded_range(minimum, maximum)
      minimum = minimum.presence
      maximum = maximum.presence
      return nil unless minimum || maximum
      return (minimum..maximum) if minimum && maximum

      minimum ? (minimum..) : (..maximum)
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
      attribute = SORT_ATTRIBUTES.fetch(sort_key).call
      primary = descending? ? attribute.desc : attribute.asc
      [primary.nulls_last, Track.arel_table[:id].asc]
    end

    def sort_key
      SORT_ATTRIBUTES.key?(params[:sort].to_s) ? params[:sort].to_s : DEFAULT_SORT
    end

    def descending?
      params[:order].to_s.casecmp("desc").zero?
    end

    def numeric?(value)
      value.to_s.match?(/\A\d+\z/)
    end

    def contains(value)
      "%#{ActiveRecord::Base.sanitize_sql_like(value.to_s)}%"
    end
  end
end
