# frozen_string_literal: true

module Rules
  # Turns one condition's operator and value into an Arel predicate over
  # `attribute`. Only positive operators arrive here; Condition maps the negated
  # ones to their twin and the compiler complements the resulting id set.
  #
  # Types and bounds are already guaranteed by RuleSetValidator (via
  # Rules::ValueChecker), so nothing here coerces or re-checks them.
  class Predicates
    BUILDERS = {
      "text" => :text,
      "number" => :numeric,
      "duration" => :numeric,
      "boolean" => :boolean,
      "date" => :date,
    }.freeze

    WILDCARDS = {
      "equals" => ->(value) { value },
      "contains" => ->(value) { "%#{value}%" },
      "starts_with" => ->(value) { "#{value}%" },
      "ends_with" => ->(value) { "%#{value}" },
    }.freeze

    COMPARISONS = { "equals" => :eq, "greater_than" => :gt, "less_than" => :lt }.freeze

    DATE_BUILDERS = {
      "in_the_last" => :since_cutoff,
      "greater_than" => :after_day,
      "less_than" => :before_day,
      "between" => :within_days,
    }.freeze

    def self.call(condition, attribute)
      new(condition, attribute).call
    end

    def initialize(condition, attribute)
      @condition = condition
      @attribute = attribute
    end

    def call
      send(BUILDERS.fetch(condition.value_type))
    end

    private

    attr_reader :condition, :attribute

    # ILIKE throughout: rule values are user-typed free text, so "gojira" has to
    # match "Gojira". With no wildcards it still uses the trigram indexes.
    def text
      return attribute.matches_any(value.map { |entry| escape(entry) }) if operator == "in"

      attribute.matches(WILDCARDS.fetch(operator).call(escaped))
    end

    def numeric
      return attribute.between(value.first..value.last) if operator == "between"

      attribute.public_send(COMPARISONS.fetch(operator), value)
    end

    def boolean
      attribute.eq(value)
    end

    # Dates are UTC and day-granular: `added_at` is a UTC timestamp and no
    # per-user timezone is stored, so "2024-01-01" means that whole UTC day.
    # "is after" therefore starts at the following midnight.
    def date
      builder = DATE_BUILDERS.fetch(operator) do
        raise ArgumentError, "unsupported date operator: #{operator.inspect}"
      end

      send(builder)
    end

    def since_cutoff
      attribute.gteq(relative_cutoff)
    end

    def after_day
      attribute.gteq(midnight(days_after(value, 1)))
    end

    def before_day
      attribute.lt(midnight(value))
    end

    def within_days
      lower, upper = value
      attribute.gteq(midnight(lower)).and(attribute.lt(midnight(days_after(upper, 1))))
    end

    def relative_cutoff
      count, unit = value.values_at("count", "unit")
      raise ArgumentError, "unsupported relative unit: #{unit.inspect}" unless
        FieldCatalog::RELATIVE_UNITS.include?(unit)

      count.public_send(unit).ago
    end

    def days_after(date, days)
      (Date.iso8601(date) + days).iso8601
    end

    def midnight(date)
      Date.iso8601(date).to_time(:utc)
    end

    def escaped
      escape(value)
    end

    def escape(entry)
      ActiveRecord::Base.sanitize_sql_like(entry.to_s)
    end

    def value
      condition.value
    end

    def operator
      condition.operator
    end
  end
end
