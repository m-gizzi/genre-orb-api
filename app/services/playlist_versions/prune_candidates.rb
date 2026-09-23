# frozen_string_literal: true

module PlaylistVersions
  # The versions a playlist no longer needs: everything past the retention window, minus
  # whatever is still current.
  #
  # Scoped to a chunk of playlists rather than the whole table on purpose. The outer
  # `rn > :keep` cannot be pushed into the window, so an unscoped statement would sort
  # every row in `playlist_versions` nightly — and the unique index is
  # (playlist_id, version_number) ASC while the window wants DESC, so that sort is real
  # work, paid even on a night with nothing to delete. A few hundred playlists at a time
  # keeps the window's input small enough to sort in memory.
  class PruneCandidates
    # Ranked, not filtered, before the retention cut: `created_at` has to ride through the
    # CTE so the grace window can be applied *after* ranking. Excluding fresh rows inside
    # the CTE would renumber the survivors and promote genuinely old versions into the
    # window we are trying to protect.
    STATEMENT = <<~SQL.squish
      WITH ranked AS (
        SELECT v.id,
               v.playlist_id,
               v.created_at,
               v.track_count,
               ROW_NUMBER() OVER (
                 PARTITION BY v.playlist_id
                 ORDER BY v.version_number DESC
               ) AS rn
        FROM playlist_versions v
        WHERE v.playlist_id IN (?)
      )
      SELECT ranked.id, ranked.track_count
      FROM ranked
      INNER JOIN playlists ON playlists.id = ranked.playlist_id
      WHERE ranked.rn > ?
        AND playlists.current_version_id IS DISTINCT FROM ranked.id
        AND ranked.created_at < ?
      ORDER BY ranked.id
    SQL

    def initialize(playlist_ids, keep:, before:)
      @playlist_ids = Array(playlist_ids)
      @keep = keep
      @before = before
    end

    def call
      return [] if playlist_ids.empty?

      PlaylistVersion.connection.select_rows(statement)
    end

    private

    attr_reader :playlist_ids, :keep, :before

    def statement
      ActiveRecord::Base.sanitize_sql_array([STATEMENT, playlist_ids, keep, before])
    end
  end
end
