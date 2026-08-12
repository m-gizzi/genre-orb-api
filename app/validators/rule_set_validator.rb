# frozen_string_literal: true

class RuleSetValidator < ActiveModel::EachValidator
  # Where in the tree a message belongs, as 1-based indexes from the root.
  Location = Data.define(:path, :kind) do
    def child(index, kind)
      Location.new(path: path + [index + 1], kind: kind)
    end

    def root?
      path.empty?
    end

    def depth
      path.length + 1
    end

    def apply(message)
      return message if root?

      I18n.t("rules.locators.#{kind}", message: message, path: path.join("."))
    end
  end

  ROOT = Location.new(path: [].freeze, kind: :group)

  def validate_each(record, attribute, value)
    return if value.blank?

    Inspection.new(value).messages.each { |message| record.errors.add(attribute, message) }
  end

  class Inspection
    Catalog = Rules::FieldCatalog
    GROUP_KEYS = %w[match rules not].freeze
    CONDITION_KEYS = %w[field operator value].freeze

    def initialize(root)
      @root = root
      @collected = []
      @nodes = 0
    end

    def messages
      @messages ||= begin
        inspect_group(@root, ROOT)
        @collected
      end
    end

    private

    def inspect_group(group, location)
      return add(location, :group_shape) unless group_shaped?(group)
      return add(location, :too_deep, max: Catalog::MAX_DEPTH) if
        location.depth > Catalog::MAX_DEPTH
      return unless within_node_limit?

      validate_match(group["match"], location)
      validate_negation(group["not"], location)
      validate_keys(group, GROUP_KEYS, location)
      inspect_children(group["rules"], location)
    end

    def inspect_children(children, location)
      return add(location, :rules_not_a_list) unless children.is_a?(Array)
      return add(location, :empty_group) if children.empty? && !location.root?

      children.each_with_index { |child, index| inspect_child(child, index, location) }
    end

    def inspect_child(child, index, location)
      if group_shaped?(child)
        inspect_group(child, location.child(index, :group))
      else
        inspect_condition(child, location.child(index, :rule))
      end
    end

    def inspect_condition(condition, location)
      return add(location, :condition_shape) unless condition.is_a?(Hash)
      return unless within_node_limit?

      validate_keys(condition, CONDITION_KEYS, location)
      return unless known_pairing?(condition, location)
      return add(location, :missing_value) unless value_given?(condition)

      Rules::ValueValidator
        .call(condition["value"], field: condition["field"], operator: condition["operator"])
        .each { |message| add_message(location, message) }
    end

    def value_given?(condition)
      condition.key?("value") || Catalog.arity(condition["operator"]) == :none
    end

    def known_pairing?(condition, location)
      field = condition["field"]
      operator = condition["operator"]

      known_field?(field, location) && known_operator?(operator, location) &&
        supported_pairing?(field, operator, location)
    end

    def validate_match(match, location)
      return if Catalog::MATCH_TYPES.include?(match)

      add(location, :unknown_match, match_types: Catalog::MATCH_TYPES.join(", "))
    end

    def validate_negation(negation, location)
      add(location, :invalid_negation) unless [nil, true, false].include?(negation)
    end

    def validate_keys(node, allowed, location)
      unknown = node.keys - allowed
      return if unknown.empty?

      add(location, :unknown_keys, keys: Rules::Excerpt.list(unknown))
    end

    def known_field?(field, location)
      return true if Catalog.field?(field)

      add(location, :unknown_field, field: Rules::Excerpt.of(field))
      false
    end

    def known_operator?(operator, location)
      return true if Catalog.operator?(operator)

      add(location, :unknown_operator, operator: Rules::Excerpt.of(operator))
      false
    end

    def supported_pairing?(field, operator, location)
      return true if Catalog.supports?(field, operator)

      add(location, :unsupported_pairing,
          operator: Rules::Excerpt.of(operator), field: Rules::Excerpt.of(field),)
      false
    end

    def group_shaped?(node)
      node.is_a?(Hash) && node.key?("match") && node.key?("rules")
    end

    def within_node_limit?
      @nodes += 1
      max = Catalog::MAX_NODES
      return true if @nodes <= max

      add(ROOT, :too_many_nodes, max: max) if @nodes == max + 1
      false
    end

    def add(location, key, **)
      add_message(location, I18n.t("rules.errors.#{key}", **))
    end

    def add_message(location, message)
      @collected << location.apply(message)
    end
  end
end
