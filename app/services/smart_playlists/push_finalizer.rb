# frozen_string_literal: true

module SmartPlaylists
  class PushFinalizer
    def initialize(push_session)
      @push_session = push_session
    end

    def call
      return if push_session.completed?

      snapshot_id = settled_snapshot_id

      ActiveRecord::Base.transaction do
        complete_version!(snapshot_id)
        swap_current_version!
        record_push!
        push_session.update!(status: :completed, completed_at: Time.current)
      end
    end

    private

    attr_reader :push_session

    def version
      @version ||= push_session.playlist_version
    end

    def target
      @target ||= push_session.smart_playlist.target_playlist
    end

    def settled_snapshot_id
      push_session.spotify_snapshot_id.presence || target.current_version&.spotify_snapshot_id
    end

    def complete_version!(snapshot_id)
      version.update!(
        status: :complete,
        track_count: version.playlist_version_tracks.count,
        spotify_snapshot_id: snapshot_id,
      )
    end

    def swap_current_version!
      target.update!(current_version_id: version.id)
    end

    def record_push!
      now = Time.current
      push_session.smart_playlist.update_columns(last_pushed_at: now, updated_at: now)
    end
  end
end
