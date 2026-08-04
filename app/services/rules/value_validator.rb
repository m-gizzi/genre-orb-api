# frozen_string_literal: true

module Rules
  class ValueValidator
    SCALARS = [String, Numeric, TrueClass, FalseClass].freeze

    ARITY_CHECKS = {
      one: :scalar_errors,
      two: :pair_errors,
      many: :list_errors,
      relative: :relative_errors,
    }.freeze

    def self.call(value, field:, operator:)
      new(value, field, operator).errors
    end

    def initialize(value, field, operator)
      @value = value
      @field = field
      @operator = operator
    end

    def errors
      check = ARITY_CHECKS[FieldCatalog.arity(@operator)]
      check ? Array(send(check)) : []
    end

    private

    attr_reader :value, :field

    def scalar_errors
      return translate(:not_a_scalar) unless scalar?(value)

      typing_errors([value])
    end

    def pair_errors
      return translate(:not_a_pair) unless pair?(value)

      typed = typing_errors(value)
      return typed if typed.any?

      lower, upper = value
      translate(:inverted_range) if (lower <=> upper).positive?
    end

    def list_errors
      return translate(:not_a_list) unless list?(value)

      max = FieldCatalog::MAX_LIST_SIZE
      return translate(:list_too_long, max: max) if value.size > max

      typing_errors(value)
    end

    def relative_errors
      return translate(:relative_shape) unless value.is_a?(Hash)

      count = value["count"]
      collected = []
      collected << translate(:relative_count) unless count.is_a?(Integer) && count.positive?

      units = FieldCatalog::RELATIVE_UNITS
      collected << translate(:relative_unit, units: units.join(", ")) unless
        units.include?(value["unit"])
      collected
    end

    def typing_errors(values)
      values.filter_map { |item| ValueChecker.error_for(field, item) }.uniq
    end

    def scalar?(item)
      SCALARS.any? { |type| item.is_a?(type) }
    end

    def pair?(item)
      item.is_a?(Array) && item.size == 2 && item.all? { |entry| scalar?(entry) }
    end

    def list?(item)
      item.is_a?(Array) && item.any? && item.all? { |entry| scalar?(entry) }
    end

    def translate(key, **)
      I18n.t("rules.errors.#{key}", **)
    end
  end
end
