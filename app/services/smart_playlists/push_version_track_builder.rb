# frozen_string_literal: true

module SmartPlaylists
  class PushVersionTrackBuilder
    def initialize(version)
      @version = version
    end

    def call(entries)
      return if entries.empty?

      PlaylistVersionTrack.upsert_all(records(entries), unique_by: %i[playlist_version_id position])
    end

    private

    attr_reader :version

    def records(entries)
      now = Time.current

      entries.map.with_index do |entry, position|
        {
          playlist_version_id: version.id,
          track_id: entry.track_id,
          position: position,
          added_at: entry.added_at,
          created_at: now,
          updated_at: now,
        }
      end
    end
  end
end
