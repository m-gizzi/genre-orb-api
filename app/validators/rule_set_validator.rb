# frozen_string_literal: true

class RuleSetValidator < ActiveModel::EachValidator
  Catalog = Rules::FieldCatalog

  MATCH_TYPES = Catalog::MATCH_TYPES
  MAX_NODES = Catalog::MAX_NODES
  MAX_DEPTH = Catalog::MAX_DEPTH

  def validate_each(record, attribute, value)
    return if value.blank?

    Inspection.new(value).messages.each { |message| record.errors.add(attribute, message) }
  end

  class Inspection
    SCALARS = [String, Numeric, TrueClass, FalseClass].freeze

    def initialize(root)
      @root = root
      @collected = []
      @nodes = 0
    end

    def messages
      @messages ||= begin
        inspect_group(@root, depth: 1)
        @collected.uniq
      end
    end

    private

    def inspect_group(group, depth:)
      return add("must have 'match' and 'rules' keys") unless group_shaped?(group)
      return add("is nested more than #{MAX_DEPTH} levels deep") if depth > MAX_DEPTH
      return unless within_node_limit?

      validate_match(group["match"])
      validate_negation(group["not"])

      children = group["rules"]
      return add("'rules' must be a list") unless children.is_a?(Array)

      children.each { |child| inspect_child(child, depth: depth) }
    end

    def inspect_child(child, depth:)
      if group_shaped?(child)
        inspect_group(child, depth: depth + 1)
      else
        inspect_condition(child)
      end
    end

    def inspect_condition(condition)
      return add("each rule must be an object") unless condition.is_a?(Hash)
      return unless within_node_limit?

      field = condition["field"]
      operator = condition["operator"]

      return unless known_field?(field) && known_operator?(operator)
      return unless supported_pairing?(field, operator)
      return add("each rule must have a value") unless condition.key?("value")

      validate_value(condition["value"], Catalog.arity(operator))
    end

    def validate_match(match)
      add("'match' must be one of: #{MATCH_TYPES.join(", ")}") unless MATCH_TYPES.include?(match)
    end

    def validate_negation(negation)
      add("'not' must be true or false") unless [nil, true, false].include?(negation)
    end

    def known_field?(field)
      return true if Catalog.field?(field)

      add("has an unknown field: #{field.inspect}")
      false
    end

    def known_operator?(operator)
      return true if Catalog.operator?(operator)

      add("has an unknown operator: #{operator.inspect}")
      false
    end

    def supported_pairing?(field, operator)
      return true if Catalog.supports?(field, operator)

      add("does not support the operator #{operator.inspect} on the field #{field.inspect}")
      false
    end

    def validate_value(value, arity)
      case arity
      when :one then validate_scalar(value)
      when :two then validate_pair(value)
      when :many then validate_list(value)
      when :relative then validate_relative(value)
      end
    end

    def validate_scalar(value)
      add("must have a single value") unless scalar?(value)
    end

    def validate_pair(value)
      return if value.is_a?(Array) && value.size == 2 && value.all? { |item| scalar?(item) }

      add("must have exactly two values when comparing a range")
    end

    def validate_list(value)
      return if value.is_a?(Array) && value.any? && value.all? { |item| scalar?(item) }

      add("must have at least one value when matching a list")
    end

    def validate_relative(value)
      return add("must have a count and a unit") unless value.is_a?(Hash)

      count = value["count"]
      add("must have a whole number count") unless count.is_a?(Integer) && count.positive?

      unit = value["unit"]
      return if Catalog::RELATIVE_UNITS.include?(unit)

      add("must use one of these units: #{Catalog::RELATIVE_UNITS.join(", ")}")
    end

    def scalar?(value)
      SCALARS.any? { |type| value.is_a?(type) } && value != ""
    end

    def group_shaped?(node)
      node.is_a?(Hash) && node.key?("match") && node.key?("rules")
    end

    def within_node_limit?
      @nodes += 1
      return true if @nodes <= MAX_NODES

      add("cannot contain more than #{MAX_NODES} rules")
      false
    end

    def add(message)
      @collected << message
    end
  end
end
