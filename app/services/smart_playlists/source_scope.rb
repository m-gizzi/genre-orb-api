# frozen_string_literal: true

module SmartPlaylists
  class SourceScope
    MEMBERSHIP_SELECT = <<~SQL.squish
      playlist_version_tracks.track_id,
      MIN(playlist_version_tracks.added_at) AS added_at
    SQL

    def initialize(smart_playlist)
      @smart_playlist = smart_playlist
    end

    def memberships
      rows.group(:track_id).select(MEMBERSHIP_SELECT)
    end

    # The same value `memberships` groups out, as a scalar correlated to tracks.id.
    # Joining the grouped relation instead lets the planner park that GROUP BY on the
    # inner side of a nested loop, where it is recomputed once per matching track; a
    # scalar subquery gives it nothing to re-execute. Costs one probe per matching
    # row, so it scales with the match count rather than the size of the source pool.
    def added_at
      Arel::Nodes::Grouping.new(earliest_add)
    end

    def track_ids
      rows.select(:track_id)
    end

    def count
      rows.distinct.count(:track_id)
    end

    private

    attr_reader :smart_playlist

    def rows
      PlaylistVersionTrack.where(playlist_version_id: version_ids)
    end

    def earliest_add
      table = membership

      Arel::SelectManager.new(table)
                         .project(table[:added_at].minimum)
                         .where(table[:track_id].eq(Track.arel_table[:id]))
                         .where(table[:playlist_version_id].in(version_ids.arel))
    end

    # Aliased so the correlated scalar can name its own columns without colliding
    # with a `playlist_version_tracks` the outer query may already have joined.
    def membership
      PlaylistVersionTrack.arel_table.alias("m")
    end

    def version_ids
      smart_playlist.source_playlists
                    .where.not(current_version_id: nil)
                    .select(:current_version_id)
    end
  end
end
