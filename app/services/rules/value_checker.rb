# frozen_string_literal: true

module Rules
  # Answers whether one scalar is a legal value for a field, given that field's
  # `value_type` and `constraints`. Shape (arity) is RuleSetValidator's business;
  # this is the primitive type and the bounds.
  class ValueChecker
    DATE_PATTERN = /\A\d{4}-\d{2}-\d{2}\z/

    CHECKS = {
      "text" => :text_error,
      "number" => :number_error,
      "duration" => :number_error,
      "boolean" => :boolean_error,
      "date" => :date_error,
    }.freeze

    class << self
      def error_for(field_key, value)
        check = CHECKS[FieldCatalog.value_type_for(field_key)]
        return unless check

        send(check, value, FieldCatalog.constraints_for(field_key))
      end

      private

      def text_error(value, constraints)
        return translate(:not_text) unless value.is_a?(String)
        return translate(:blank_text) if value.strip.empty?

        max = constraints[:max_length]
        translate(:text_too_long, max: max) if max && value.length > max
      end

      def number_error(value, constraints)
        return translate(:not_a_number) unless value.is_a?(Integer)

        min = constraints.fetch(:min, -Float::INFINITY)
        max = constraints.fetch(:max, Float::INFINITY)
        return if value.between?(min, max)

        translate(:out_of_range, min: min, max: max)
      end

      def boolean_error(value, _constraints)
        translate(:not_a_boolean) unless [true, false].include?(value)
      end

      def date_error(value, _constraints)
        return translate(:not_a_date) unless value.is_a?(String) && value.match?(DATE_PATTERN)

        Date.iso8601(value)
        nil
      rescue Date::Error
        translate(:not_a_date)
      end

      def translate(key, **)
        I18n.t("rules.errors.#{key}", **)
      end
    end
  end
end
