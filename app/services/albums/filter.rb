# frozen_string_literal: true

module Albums
  class Filter
    SORT_NODES = {
      "title" => -> { Album.arel_table[:title] },
      "release_year" => -> { Album.arel_table[:release_year] },
    }.freeze

    DEFAULT_SORT = "title"

    def initialize(user, params)
      @user = user
      @params = params
    end

    def call
      relation = user.library_albums.includes(:artists)
      relation = filter_search(relation)
      relation = filter_genre(relation)
      relation = filter_year(relation)
      relation.order(order_term)
    end

    private

    attr_reader :user, :params

    def filter_search(relation)
      value = params[:search]
      return relation if value.blank?

      relation.where("albums.title ILIKE ?", contains(value))
    end

    def filter_genre(relation)
      return relation if params[:genre].blank?

      album_ids = Track.where(id: genre_track_ids).where.not(album_id: nil).select(:album_id)
      relation.where(id: album_ids)
    end

    def filter_year(relation)
      range = bounded_range(params[:year_min], params[:year_max])
      range ? relation.where(albums: { release_year: range }) : relation
    end

    def bounded_range(minimum, maximum)
      minimum = minimum.presence
      maximum = maximum.presence
      return nil unless minimum || maximum
      return (minimum..maximum) if minimum && maximum

      minimum ? (minimum..) : (..maximum)
    end

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

    def order_term
      node = SORT_NODES.fetch(sort_key).call
      descending? ? node.desc.nulls_last : node.asc.nulls_first
    end

    def sort_key
      SORT_NODES.key?(params[:sort].to_s) ? params[:sort].to_s : DEFAULT_SORT
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
