# frozen_string_literal: true

module Genres
  class Filter < Filters::Base
    COUNTS_ALIAS = "genre_track_counts"

    sorts(
      {
        "name" => -> { Genre.arel_table[:name] },
        "track_count" => -> { Arel.sql("#{COUNTS_ALIAS}.track_count") },
      },
      default: "name",
      nulls: :none,
    )

    # `tracks` narrows the genre list — and its counts — to one track set. It defaults to
    # everything the user holds, which is the library-wide genre cloud.
    def initialize(user, params, tracks: nil)
      super(user, params)
      @tracks = tracks
    end

    def call
      relation = search(base_relation, Genre.arel_table[:name])
      relation = RuleUsage.new(user).apply(relation, params[:rule_usage])
      relation.order(*sort.terms)
    end

    # Counts for one page of results, kept off the joined SELECT so Pagy can still count
    # the relation.
    def track_counts_for(genres)
      counter.for_genres(genres)
    end

    private

    def tracks
      @tracks ||= user.library_tracks
    end

    def counter
      @counter ||= TrackCounts.new(genres_scope, tracks)
    end

    def genres_scope
      @genres_scope ||= Genres::EffectiveScope.new(user, apply_blocklist: !include_blocked?)
    end

    def include_blocked?
      ActiveModel::Type::Boolean.new.cast(params[:include_blocked]) || false
    end

    def base_relation
      return Genre.joins(counter.join(COUNTS_ALIAS)) if sort.key == "track_count"

      Genre.where(id: counter.genre_ids)
    end
  end
end
