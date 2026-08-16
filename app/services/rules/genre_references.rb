# frozen_string_literal: true

module Rules
  # Which genres a rule tree names. Genre rules match on the *name*, not an id, so this
  # returns strings — normalized the same way the compiler normalizes them on the read path,
  # or the two would disagree about "  Death   Metal ".
  #
  # `contains` is kept apart from the exact operators because it names a shape rather than a
  # genre: `genre contains "metal"` really does reach `death metal`, and calling those
  # unused would send a user off to block genres their rules depend on.
  #
  # `is_set` / `is_not_set` carry no value and reference nothing in particular.
  class GenreReferences
    FIELD = "genre"
    EXACT_OPERATORS = %w[equals not_equals in not_in].freeze
    PATTERN_OPERATORS = %w[contains].freeze

    Result = Struct.new(:names, :patterns, keyword_init: true) do
      def empty? = names.empty? && patterns.empty?
    end

    def self.extract(rules)
      new(rules).result
    end

    def initialize(rules)
      @rules = rules
    end

    def result
      names = []
      patterns = []
      collect(rules) { |operator, value| (exact?(operator) ? names : patterns) << value }

      Result.new(names: names.uniq, patterns: patterns.uniq)
    end

    private

    attr_reader :rules

    def collect(node, &)
      return unless node.is_a?(Hash)
      return Array(node["rules"]).each { |child| collect(child, &) } if node.key?("rules")
      return unless node["field"] == FIELD

      emit(node, &)
    end

    def emit(node)
      operator = node["operator"]
      return unless exact?(operator) || pattern?(operator)

      Array(node["value"]).grep(String).each do |value|
        name = Genre.normalize_name(value)
        yield(operator, name) if name.present?
      end
    end

    def exact?(operator) = EXACT_OPERATORS.include?(operator)
    def pattern?(operator) = PATTERN_OPERATORS.include?(operator)
  end
end
