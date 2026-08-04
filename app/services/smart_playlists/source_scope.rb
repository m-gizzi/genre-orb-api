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

    def version_ids
      smart_playlist.source_playlists
                    .where.not(current_version_id: nil)
                    .select(:current_version_id)
    end
  end
end
