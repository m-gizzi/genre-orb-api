# frozen_string_literal: true

module SmartPlaylists
  # Derives the plan from the session's own records, so the planner and the phase
  # advancer reach the same batches without carrying them between jobs.
  class PushBatches
    BATCH_SIZE = SpotifyAdapter::TRACK_BATCH_LIMIT

    def initialize(push_session)
      @push_session = push_session
    end

    def desired
      @desired ||= spotify_ids_for(push_session.playlist_version)
    end

    def current
      @current ||= spotify_ids_for(push_session.baseline_version)
    end

    def diff
      @diff ||= PushDiff.new(desired: desired, current: current)
    end

    def slices(spotify_ids)
      spotify_ids.each_slice(BATCH_SIZE).to_a
    end

    private

    attr_reader :push_session

    def spotify_ids_for(version)
      return [] unless version

      version.playlist_version_tracks.order(:position).joins(:track).pluck(Arel.sql("tracks.spotify_id"))
    end
  end
end
