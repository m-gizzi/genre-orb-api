# frozen_string_literal: true

module Rules
  class FieldCatalog
    MAX_DEPTH = 5
    MAX_NODES = 100
    MAX_STRING_LENGTH = 200
    MAX_LIST_SIZE = 50
    MATCH_TYPES = %w[all any].freeze
    RELATIVE_UNITS = %w[days weeks months years].freeze

    TEXT_LIMITS = { max_length: MAX_STRING_LENGTH }.freeze
    YEAR_LIMITS = { min: 1900, max: 2100 }.freeze
    DURATION_LIMITS = { min: 0, max: 86_400_000 }.freeze # milliseconds; 24h outer bound
    POPULARITY_LIMITS = { min: 0, max: 100 }.freeze      # Spotify's documented range
    NO_LIMITS = {}.freeze

    # Arity decides how `value` is shaped, and which widget the builder renders.
    #   one      → a scalar
    #   two      → a [min, max] pair
    #   many     → a non-empty list of scalars
    #   relative → { "count" => Integer, "unit" => RELATIVE_UNITS }
    #   none     → null; the operator asks whether the field has any value at all
    OPERATORS = {
      "equals" => :one,
      "not_equals" => :one,
      "contains" => :one,
      "starts_with" => :one,
      "ends_with" => :one,
      "greater_than" => :one,
      "less_than" => :one,
      "between" => :two,
      "in" => :many,
      "not_in" => :many,
      "in_the_last" => :relative,
      "not_in_the_last" => :relative,
      "is_set" => :none,
      "is_not_set" => :none,
    }.freeze

    # Operator vocabularies, each mapping an operator to how it reads for that
    # kind of field — "is after" for a year, "is longer than" for a duration.
    VOCABULARIES = {
      entity: {
        "equals" => "is",
        "not_equals" => "is not",
        "contains" => "contains",
        "in" => "is any of",
        "not_in" => "is none of",
        "is_set" => "is set",
        "is_not_set" => "is not set",
      },
      playlist: {
        "in" => "is any of",
        "not_in" => "is none of",
      },
      title: {
        "equals" => "is",
        "not_equals" => "is not",
        "contains" => "contains",
        "starts_with" => "starts with",
        "ends_with" => "ends with",
      },
      year: {
        "equals" => "is",
        "not_equals" => "is not",
        "greater_than" => "is after",
        "less_than" => "is before",
        "between" => "is between",
      },
      duration: {
        "greater_than" => "is longer than",
        "less_than" => "is shorter than",
        "between" => "is between",
      },
      popularity: {
        "equals" => "is",
        "greater_than" => "is above",
        "less_than" => "is below",
        "between" => "is between",
      },
      boolean: { "equals" => "is" },
      date: {
        "in_the_last" => "in the last",
        "not_in_the_last" => "not in the last",
        "greater_than" => "is after",
        "less_than" => "is before",
        "between" => "is between",
      },
    }.freeze

    # `suggest` names the autocomplete endpoint that feeds the value input.
    # Entity fields match on name, not id, so a rule stays readable and keeps
    # working when a record is pruned and re-synced. Playlist is the exception:
    # names are neither unique nor stable, so it references the local record.
    FIELDS = [
      { key: "genre", label: "Genre", value_type: "text", suggest: "genres",
        constraints: TEXT_LIMITS, operators: VOCABULARIES[:entity], },
      { key: "artist", label: "Artist", value_type: "text", suggest: "artists",
        constraints: TEXT_LIMITS, operators: VOCABULARIES[:entity], },
      { key: "album", label: "Album", value_type: "text", suggest: "albums",
        constraints: TEXT_LIMITS, operators: VOCABULARIES[:entity], },
      { key: "title", label: "Title", value_type: "text", suggest: nil,
        constraints: TEXT_LIMITS, operators: VOCABULARIES[:title], },
      { key: "year", label: "Release year", value_type: "number", suggest: nil,
        constraints: YEAR_LIMITS, operators: VOCABULARIES[:year], },
      { key: "duration", label: "Duration", value_type: "duration", suggest: nil,
        constraints: DURATION_LIMITS, operators: VOCABULARIES[:duration], },
      { key: "popularity", label: "Popularity", value_type: "number", suggest: nil,
        constraints: POPULARITY_LIMITS, operators: VOCABULARIES[:popularity], },
      { key: "explicit", label: "Explicit", value_type: "boolean", suggest: nil,
        constraints: NO_LIMITS, operators: VOCABULARIES[:boolean], },
      { key: "date_added", label: "Date added", value_type: "date", suggest: nil,
        constraints: NO_LIMITS, operators: VOCABULARIES[:date], },
      { key: "playlist", label: "Playlist", value_type: "playlist", suggest: "playlists",
        constraints: NO_LIMITS, operators: VOCABULARIES[:playlist], },
    ].freeze

    BY_KEY = FIELDS.index_by { |field| field[:key] }.freeze

    class << self
      def fields
        FIELDS
      end

      def field_keys
        BY_KEY.keys
      end

      def field(key)
        BY_KEY[key]
      end

      def field?(key)
        BY_KEY.key?(key)
      end

      def operator?(operator)
        OPERATORS.key?(operator)
      end

      def arity(operator)
        OPERATORS[operator]
      end

      def operators_for(key)
        vocabulary = field(key)&.fetch(:operators)
        vocabulary ? vocabulary.keys : []
      end

      def supports?(key, operator)
        operators_for(key).include?(operator)
      end

      def value_type_for(key)
        field(key)&.fetch(:value_type)
      end

      def constraints_for(key)
        field(key)&.fetch(:constraints) || NO_LIMITS
      end

      def to_h
        @to_h ||= {
          max_depth: MAX_DEPTH,
          max_nodes: MAX_NODES,
          max_string_length: MAX_STRING_LENGTH,
          max_list_size: MAX_LIST_SIZE,
          match_types: MATCH_TYPES,
          relative_units: RELATIVE_UNITS,
          operators: OPERATORS.transform_values { |arity| { arity: arity } },
          fields: FIELDS.map { |field| serialize_field(field) },
        }.freeze
      end

      def digest
        @digest ||= ActiveSupport::Digest.hexdigest(to_h.to_json)
      end

      private

      def serialize_field(field)
        field.slice(:key, :label, :value_type, :suggest, :constraints).merge(
          operators: field[:operators].map { |key, label| { key: key, label: label } },
        )
      end
    end
  end
end
