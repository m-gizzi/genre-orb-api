# frozen_string_literal: true

module Genres
  class Layers
    def initialize(preferences, table)
      @preferences = preferences
      @table = table
    end

    # Source values come from GenreSourced::SOURCES, never from a request, so interpolating
    # them is safe. An empty list means the user disabled every source.
    def source_filter
      return nil if preferences.all_sources_enabled?

      values = preferences.enabled_source_values
      return "FALSE" if values.empty?

      "#{table}.source IN (#{values.join(", ")})"
    end

    def confidence_floor
      floors = preferences.floors_by_value
      return nil if floors.empty?

      arms = floors.map { |source, floor| "WHEN #{source} THEN #{floor.to_f}" }.join(" ")
      "#{table}.confidence >= CASE #{table}.source #{arms} ELSE 0 END"
    end

    def blocklist
      ids = preferences.blocked_genre_ids
      return nil if ids.empty?

      ActiveRecord::Base.sanitize_sql_array(["#{table}.genre_id NOT IN (?)", ids])
    end

    def all
      [source_filter, confidence_floor, blocklist].compact
    end

    private

    attr_reader :preferences, :table
  end
end
