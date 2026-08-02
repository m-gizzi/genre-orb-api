# frozen_string_literal: true

class RuleSetValidator < ActiveModel::EachValidator
  MATCH_TYPES = %w[all any].freeze
  FIELDS = %w[genre artist album title year date_added duration play_count last_played].freeze
  OPERATORS = %w[
    equals not_equals contains starts_with ends_with
    greater_than less_than between in not_in
  ].freeze

  MAX_NODES = 100
  MAX_DEPTH = 5

  def validate_each(record, attribute, value)
    return if value.blank?

    Inspection.new(value).messages.each { |message| record.errors.add(attribute, message) }
  end

  class Inspection
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

      validate_field(condition["field"])
      validate_operator(condition["operator"])
      add("each rule must have a value") unless condition.key?("value")
    end

    def validate_match(match)
      add("'match' must be one of: #{MATCH_TYPES.join(", ")}") unless MATCH_TYPES.include?(match)
    end

    def validate_negation(negation)
      add("'not' must be true or false") unless [nil, true, false].include?(negation)
    end

    def validate_field(field)
      add("has an unknown field: #{field.inspect}") unless FIELDS.include?(field)
    end

    def validate_operator(operator)
      add("has an unknown operator: #{operator.inspect}") unless OPERATORS.include?(operator)
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
