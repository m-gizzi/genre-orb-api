# frozen_string_literal: true

module Spotify
  class PlaylistVersionTrackBuilder
    def initialize(version)
      @version = version
    end

    def call(spotify_items, tracks_by_spotify_id, offset: 0)
      records = build_records(spotify_items, tracks_by_spotify_id, offset)
      return if records.empty?

      PlaylistVersionTrack.upsert_all(
        records,
        unique_by: %i[playlist_version_id track_id],
        update_only: %i[position added_at],
      )
    end

    private

    def build_records(spotify_items, tracks_by_spotify_id, offset)
      spotify_items.filter_map.with_index do |item, idx|
        track = tracks_by_spotify_id[item.dig("track", "id")]
        next unless track

        {
          playlist_version_id: @version.id,
          track_id: track.id,
          position: offset + idx,
          added_at: item["added_at"],
          created_at: Time.current,
          updated_at: Time.current,
        }
      end
    end
  end
end
