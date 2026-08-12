# frozen_string_literal: true

module SmartPlaylists
  class PushTrackSet
    PUSH_LIMIT = SpotifyAdapter::PLAYLIST_TRACK_LIMIT

    Entry = Struct.new(:track_id, :added_at, keyword_init: true)

    def initialize(evaluator)
      @evaluator = evaluator
    end

    def entries
      @entries ||= guarded { build_entries }
    end

    def total_match_count
      @total_match_count ||= guarded { evaluator.count }
    end

    def sampled?
      total_match_count > PUSH_LIMIT
    end

    private

    attr_reader :evaluator

    def guarded(&)
      QueryTimeout.guard(QueryTimeout::PUSH_TIMEOUT_MS, &)
    end

    def build_entries
      rows = evaluator.in_canonical_order(selected_scope).pluck(
        Arel.sql("tracks.id"),
        Arel.sql("#{Evaluator::MEMBERSHIPS_ALIAS}.added_at"),
      )

      rows.map { |id, added_at| Entry.new(track_id: id, added_at: added_at) }
    end

    def selected_scope
      sampled? ? Track.where(id: sample_ids) : evaluator.scope
    end

    def sample_ids
      evaluator.scope.order(Arel.sql("RANDOM()")).limit(PUSH_LIMIT).pluck(:id)
    end
  end
end
