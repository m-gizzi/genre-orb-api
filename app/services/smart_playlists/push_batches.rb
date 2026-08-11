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
      @current ||= spotify_ids_for(target.current_version)
    end

    def diff
      @diff ||= PushDiff.new(desired: desired, current: current)
    end

    def slices(spotify_ids)
      spotify_ids.each_slice(BATCH_SIZE).to_a
    end

    def diff_cost
      batch_count(diff.to_remove) + batch_count(diff.to_add)
    end

    def replace_cost
      batch_count(desired)
    end

    private

    attr_reader :push_session

    def target
      push_session.smart_playlist.target_playlist
    end

    def spotify_ids_for(version)
      return [] unless version

      version.playlist_version_tracks.order(:position).joins(:track).pluck(Arel.sql("tracks.spotify_id"))
    end

    def batch_count(spotify_ids)
      (spotify_ids.size.to_f / BATCH_SIZE).ceil
    end
  end
end
