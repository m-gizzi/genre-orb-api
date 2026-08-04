# frozen_string_literal: true

module SmartPlaylists
  # Runs a rule set against its source pool.
  #
  # Pass `rules:` to evaluate a set the record does not hold yet — that is how
  # the builder previews an unsaved draft.
  #
  # #matches is lazy; callers materialize it inside QueryTimeout.guard.
  class Evaluator
    MEMBERSHIPS_ALIAS = "source_memberships"
    ORDER = "#{MEMBERSHIPS_ALIAS}.added_at DESC NULLS LAST".freeze

    def initialize(smart_playlist, rules: smart_playlist.rules)
      @smart_playlist = smart_playlist
      @rules = rules
    end

    def matches
      scoped.with_catalog_associations
            .joins(memberships_join)
            .order(Arel.sql(ORDER), Track.arel_table[:id].asc)
    end

    delegate :count, to: :scoped

    def source_track_count
      source.count
    end

    private

    attr_reader :smart_playlist, :rules

    def scoped
      Track.where(id: source.track_ids).where(predicate)
    end

    def predicate
      Rules::Compiler.new(source.memberships).call(rules)
    end

    def source
      @source ||= SourceScope.new(smart_playlist)
    end

    def memberships_join
      "INNER JOIN (#{source.memberships.to_sql}) #{MEMBERSHIPS_ALIAS} " \
        "ON #{MEMBERSHIPS_ALIAS}.track_id = tracks.id"
    end
  end
end
