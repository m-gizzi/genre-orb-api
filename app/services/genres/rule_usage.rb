# frozen_string_literal: true

module Genres
  # Splits the genre list by whether any of the user's smart playlist rules names it —
  # which is how you find the junk worth blocking, and how you avoid blocking something a
  # rule depends on.
  #
  # Every smart playlist counts, enabled or not: a disabled one still names the genre and
  # can be switched back on, so calling its genres unused would be a trap.
  class RuleUsage
    USED = "used"
    UNUSED = "unused"
    VALUES = [USED, UNUSED].freeze

    def initialize(user)
      @user = user
    end

    def apply(relation, value)
      return relation unless VALUES.include?(value)
      # No rule names a genre, so nothing is used and everything is unused.
      return used?(value) ? relation.none : relation if references.empty?

      used?(value) ? relation.where(condition) : relation.where.not(condition)
    end

    private

    attr_reader :user

    def used?(value) = value == USED

    def references
      @references ||= Rules::GenreReferences.extract(all_rules)
    end

    # One synthetic group, so the walk happens once over every rule set the user holds
    # rather than once per smart playlist.
    def all_rules
      { "match" => "any", "rules" => user.smart_playlists.pluck(:rules) }
    end

    def condition
      [exact_condition, pattern_condition].compact.join(" OR ")
    end

    def exact_condition
      return nil if references.names.empty?

      ActiveRecord::Base.sanitize_sql_array(["genres.name IN (?)", references.names])
    end

    # `genre contains "metal"` reaches every genre whose name holds it, so the pattern has
    # to be matched the same way the rule engine matches it — ILIKE, not equality.
    def pattern_condition
      return nil if references.patterns.empty?

      patterns = references.patterns.map { |pattern| "%#{pattern}%" }
      ActiveRecord::Base.sanitize_sql_array(["genres.name ILIKE ANY (ARRAY[?])", patterns])
    end
  end
end
