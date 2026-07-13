# frozen_string_literal: true

module Artists
  class Filter
    def initialize(user, params)
      @user = user
      @params = params
    end

    def call
      relation = user.library_artists.order("artists.name")
      relation = filter_search(relation)
      filter_genre(relation)
    end

    private

    attr_reader :user, :params

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

    def numeric?(value)
      value.to_s.match?(/\A\d+\z/)
    end

    def contains(value)
      "%#{ActiveRecord::Base.sanitize_sql_like(value.to_s)}%"
    end
  end
end
