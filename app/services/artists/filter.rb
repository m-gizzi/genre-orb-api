# frozen_string_literal: true

module Artists
  class Filter
    SORT_NODES = {
      "name" => -> { Artist.arel_table[:name] },
      "popularity" => -> { Arel.sql("(artists.metadata->>'popularity')::int") },
      "followers" => -> { Arel.sql("(artists.metadata->>'followers')::int") },
    }.freeze

    DEFAULT_SORT = "name"

    def initialize(user, params)
      @user = user
      @params = params
    end

    def call
      Artist.where(id: filtered_ids).order(order_term)
    end

    private

    attr_reader :user, :params

    def filtered_ids
      relation = user.library_artists
      relation = filter_search(relation)
      relation = filter_genre(relation)
      relation.reselect("artists.id")
    end

    def filter_search(relation)
      value = params[:search]
      return relation if value.blank?

      relation.where("artists.name ILIKE ?", contains(value))
    end

    def filter_genre(relation)
      return relation if params[:genre].blank?

      artist_ids = TrackArtist.where(track_id: genre_track_ids).select(:artist_id)
      relation.where(id: artist_ids)
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
