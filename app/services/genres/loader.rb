# frozen_string_literal: true

module Genres
  class Loader
    Entry = Struct.new(:genre_id, :name, :source, :confidence, keyword_init: true)

    EMPTY = [].freeze

    def initialize(user)
      @scope = EffectiveScope.new(user)
    end

    def for_tracks(tracks)
      grouped(scope.tracks.where(track_id: ids(tracks)), :track_id)
    end

    def for_artists(artists)
      grouped(scope.artists.where(artist_id: ids(artists)), :artist_id)
    end

    private

    attr_reader :scope

    def ids(records)
      Array(records).map { |record| record.try(:id) || record }
    end

    def grouped(relation, key)
      rows = relation.joins(:genre).order("genres.name")
                     .pluck(key, :genre_id, "genres.name", :source, :confidence)

      rows.group_by(&:first).transform_values { |tuples| entries(tuples) }
    end

    def entries(tuples)
      tuples.map { |tuple| entry(tuple) }
    end

    def entry(tuple)
      Entry.new(genre_id: tuple[1], name: tuple[2], source: tuple[3], confidence: tuple[4])
    end
  end
end
