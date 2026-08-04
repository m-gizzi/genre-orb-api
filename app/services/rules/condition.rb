# frozen_string_literal: true

module Rules
  # One condition node from a rule tree, read through the catalog.
  #
  # Negated operators are exposed as their positive twin plus `negated?`, so the
  # compiler builds the positive track-id set once and complements it. That is
  # what keeps "is not" on a multi-valued field meaning "has no matching value"
  # rather than "has some non-matching value".
  class Condition
    COMPLEMENTS = {
      "not_equals" => "equals",
      "not_in" => "in",
      "not_in_the_last" => "in_the_last",
    }.freeze

    # Genre names are stored normalized, so a rule's value has to be normalized
    # the same way before it can match.
    NORMALIZERS = { "genre" => ->(entry) { Genre.normalize_name(entry) } }.freeze

    def initialize(node)
      @node = node
    end

    def field
      @node["field"]
    end

    def operator
      COMPLEMENTS.fetch(raw_operator, raw_operator)
    end

    def negated?
      COMPLEMENTS.key?(raw_operator)
    end

    def value_type
      FieldCatalog.value_type_for(field)
    end

    def value
      normalizer = NORMALIZERS[field]
      normalizer ? normalize(@node["value"], normalizer) : @node["value"]
    end

    private

    def raw_operator
      @node["operator"]
    end

    def normalize(value, normalizer)
      case value
      when Array then value.map { |entry| normalizer.call(entry) }
      when String then normalizer.call(value)
      else value
      end
    end
  end
end
