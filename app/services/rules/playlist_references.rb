# frozen_string_literal: true

module Rules
  class PlaylistReferences
    FIELD = "playlist"

    def self.extract(rules)
      new(rules).ids
    end

    def initialize(rules)
      @rules = rules
    end

    def ids
      collect(@rules).uniq
    end

    private

    def collect(node)
      return [] unless node.is_a?(Hash)
      return group_ids(node["rules"]) if node.key?("rules")
      return [] unless node["field"] == FIELD

      Array(node["value"]).grep(Integer)
    end

    def group_ids(children)
      return [] unless children.is_a?(Array)

      children.flat_map { |child| collect(child) }
    end
  end
end
