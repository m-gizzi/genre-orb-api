# frozen_string_literal: true

module Rules
  # Walks a rule tree and returns one Arel predicate for `Track.where(...)`.
  #
  # Returning an Arel node rather than a relation is deliberate: AND, OR and NOT
  # then compose freely, without ActiveRecord::Relation#or's structural
  # compatibility rules.
  class Compiler
    def initialize(memberships)
      @conditions = ConditionCompiler.new(memberships)
    end

    def call(node)
      group?(node) ? group(node) : conditions.call(node)
    end

    private

    attr_reader :conditions

    def group?(node)
      node.is_a?(Hash) && node.key?("match") && node.key?("rules")
    end

    def group(node)
      predicate = combine(node["match"], node["rules"].map { |child| call(child) })
      node["not"] ? negate(predicate) : predicate
    end

    def combine(match, predicates)
      return identity(match) if predicates.empty?
      return predicates.first if predicates.one?

      Arel::Nodes::Grouping.new(junction(match).new(predicates))
    end

    def junction(match)
      any?(match) ? Arel::Nodes::Or : Arel::Nodes::And
    end

    def negate(predicate)
      Arel::Nodes::Not.new(Arel::Nodes::Grouping.new(predicate))
    end

    def identity(match)
      any?(match) ? Arel::Nodes::False.new : Arel::Nodes::True.new
    end

    def any?(match)
      match == "any"
    end
  end
end
