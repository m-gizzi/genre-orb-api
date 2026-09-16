# frozen_string_literal: true

module SmartPlaylists
  # Runs a rule set against its source pool, and remembers the result when the
  # rule set is the one the playlist actually holds.
  #
  # Pass `rules:` to evaluate a set the record does not hold yet — that is how the
  # builder evaluates an unsaved draft, and why such a run is not recorded.
  #
  # #matches is lazy; callers materialize it inside QueryTimeout.guard.
  class Evaluator
    # Exposed so a caller ordering by it can also select it — see PushTrackSet.
    delegate :added_at, to: :source

    def initialize(smart_playlist, rules: smart_playlist.rules)
      @smart_playlist = smart_playlist
      @rules = rules
    end

    def matches
      in_canonical_order(scope.with_catalog_associations)
    end

    def scope
      Track.where(id: source.track_ids).where(predicate)
    end

    def in_canonical_order(relation)
      relation.order(added_at.desc.nulls_last, Track.arel_table[:id].asc)
    end

    def count
      @count ||= scope.count
    end

    def source_track_count
      source.count
    end

    def records?
      smart_playlist.ready? && rules.as_json == smart_playlist.rules.as_json
    end

    def record!
      return unless records?

      now = Time.current
      smart_playlist.update_columns(match_count: count, last_evaluated_at: now, updated_at: now)
      now
    end

    private

    attr_reader :smart_playlist, :rules

    def predicate
      Rules::Compiler.new(source.memberships, smart_playlist.user).call(rules)
    end

    def source
      @source ||= SourceScope.new(smart_playlist)
    end
  end
end
