# frozen_string_literal: true

module PlaylistVersions
  # Where the last sweep ran out of budget.
  #
  # Without it every run restarts at the lowest playlist id, so a sweep that cannot
  # finish inside its budget re-walks the same prefix each night and the tail is never
  # reached. The prefix gets cheap once pruned, but the ranking query is still paid for
  # every chunk before the run reaches new ground.
  #
  # Redis rather than a table because losing the key costs one redundant sweep from the
  # top — exactly the behaviour this replaces — so it needs no durability guarantee.
  class SweepCursor
    KEY = "genre_orb:playlist_versions:prune_cursor"
    TTL = 7.days

    class << self
      # Clamped at zero so a missing key, an expired one, or a hand-edited value can only
      # ever cost a sweep from the top, never skip playlists.
      def read
        [AppRedis.with { |redis| redis.call("GET", KEY) }.to_i, 0].max
      end

      def write(playlist_id)
        AppRedis.with { |redis| redis.call("SET", KEY, playlist_id.to_i, "EX", TTL.to_i) }
      end

      def clear
        AppRedis.with { |redis| redis.call("DEL", KEY) }
      end
    end
  end
end
