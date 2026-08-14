# frozen_string_literal: true

module Genres
  class Preferences
    DEFAULT_ENABLED = true
    DEFAULT_FLOOR = 0.0

    # `user` is not configurable: you cannot disable your own edits. It is also absent
    # from the catalog tables the source filter applies to.
    CONFIGURABLE = (GenreSourced::SOURCES.keys - [:user]).freeze

    def initialize(user, apply_blocklist: true)
      @user = user
      @apply_blocklist = apply_blocklist
      @stored = user.genre_source_preferences.presence || {}
    end

    def enabled?(source)
      setting(source).fetch("enabled", DEFAULT_ENABLED)
    end

    def floor_for(source)
      setting(source).fetch("min_confidence", DEFAULT_FLOOR).to_f
    end

    def all_sources_enabled?
      CONFIGURABLE.all? { |source| enabled?(source) }
    end

    def enabled_source_values
      CONFIGURABLE.filter_map { |source| GenreSourced::SOURCES.fetch(source) if enabled?(source) }
    end

    def floors_by_value
      CONFIGURABLE.each_with_object({}) do |source, floors|
        floor = floor_for(source)
        floors[GenreSourced::SOURCES.fetch(source)] = floor if enabled?(source) && floor > DEFAULT_FLOOR
      end
    end

    def blocked_genre_ids
      return [] unless apply_blocklist

      @blocked_genre_ids ||= user.blocked_genres.pluck(:genre_id)
    end

    def neutral?
      all_sources_enabled? && floors_by_value.empty? && blocked_genre_ids.empty?
    end

    def to_h
      CONFIGURABLE.index_with do |source|
        { enabled: enabled?(source), min_confidence: floor_for(source) }
      end
    end

    private

    attr_reader :user, :stored, :apply_blocklist

    def setting(source)
      stored[source.to_s] || {}
    end
  end
end
