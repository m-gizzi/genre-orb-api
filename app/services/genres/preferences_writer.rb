# frozen_string_literal: true

module Genres
  class PreferencesWriter
    class InvalidPreference < StandardError; end

    def initialize(user, attributes = {})
      @user = user
      @attributes = attributes
    end

    def call
      user.transaction do
        write_sources if attributes.key?(:sources)
        replace_blocklist if attributes.key?(:blocked_genre_ids)
      end
      Preferences.new(user.reload)
    end

    private

    attr_reader :user, :attributes

    def write_sources
      merged = user.genre_source_preferences.deep_merge(sanitized_sources)
      user.update!(genre_source_preferences: merged)
    end

    def sanitized_sources
      (attributes[:sources] || {}).to_h.each_with_object({}) do |(name, setting), sources|
        source = name.to_sym
        raise InvalidPreference, name.to_s unless Preferences::CONFIGURABLE.include?(source)

        sources[name.to_s] = source_setting(setting)
      end
    end

    def source_setting(setting)
      {}.tap do |values|
        values["enabled"] = ActiveModel::Type::Boolean.new.cast(setting[:enabled]) if setting.key?(:enabled)
        values["min_confidence"] = confidence(setting[:min_confidence]) if setting.key?(:min_confidence)
      end
    end

    def confidence(value)
      float = value.to_f
      raise InvalidPreference, "min_confidence" unless float.between?(0.0, 1.0)

      float
    end

    # An empty list clears the blocklist, because `where.not(genre_id: [])` matches every
    # row — which is the behaviour we want and worth naming, since it reads like a no-op.
    def replace_blocklist
      ids = Genre.where(id: Array(attributes[:blocked_genre_ids])).pluck(:id)
      user.blocked_genres.where.not(genre_id: ids).destroy_all
      add_blocked(ids - user.blocked_genres.pluck(:genre_id))
    end

    def add_blocked(genre_ids)
      genre_ids.each { |genre_id| user.blocked_genres.create!(genre_id: genre_id) }
    end
  end
end
