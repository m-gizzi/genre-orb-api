# frozen_string_literal: true

module Rules
  class ValueValidator
    SCALARS = [String, Numeric, TrueClass, FalseClass].freeze
    RELATIVE_KEYS = %w[count unit].freeze

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
      return translate(:entry_shape) unless all_scalars?(value)

      typed = typing_errors(value)
      return typed if typed.any?

      order_error(*value)
    end

    def list_errors
      return translate(:not_a_list) unless list?(value)

      max = FieldCatalog::MAX_LIST_SIZE
      return translate(:list_too_long, max: max) if value.size > max
      return translate(:entry_shape) unless all_scalars?(value)

      typing_errors(value)
    end

    def relative_errors
      return translate(:relative_shape) unless value.is_a?(Hash)

      [count_error, unit_error, unknown_keys_error].compact
    end

    def order_error(lower, upper)
      order = lower <=> upper
      return translate(:incomparable_range) if order.nil?

      translate(:inverted_range) if order.positive?
    end

    def count_error
      count = value["count"]
      translate(:relative_count) unless count.is_a?(Integer) && count.positive?
    end

    def unit_error
      units = FieldCatalog::RELATIVE_UNITS
      return if units.include?(value["unit"])

      translate(:relative_unit, units: units.join(", "))
    end

    def unknown_keys_error
      unknown = value.keys - RELATIVE_KEYS
      return if unknown.empty?

      translate(:unknown_keys, keys: Excerpt.list(unknown))
    end

    def typing_errors(values)
      values.filter_map { |item| ValueChecker.error_for(field, item) }.uniq
    end

    def scalar?(item)
      SCALARS.any? { |type| item.is_a?(type) }
    end

    def all_scalars?(items)
      items.all? { |entry| scalar?(entry) }
    end

    def pair?(item)
      item.is_a?(Array) && item.size == 2
    end

    def list?(item)
      item.is_a?(Array) && !item.empty?
    end

    def translate(key, **)
      I18n.t("rules.errors.#{key}", **)
    end
  end
end
