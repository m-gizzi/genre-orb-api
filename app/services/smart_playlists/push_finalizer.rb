# frozen_string_literal: true

module SmartPlaylists
  class PushFinalizer
    def initialize(push_session, adapter:)
      @push_session = push_session
      @adapter = adapter
    end

    def call
      return if push_session.completed?

      snapshot_id = authoritative_snapshot_id

      ActiveRecord::Base.transaction do
        complete_version!(snapshot_id)
        swap_current_version!
        push_session.update!(status: :completed, completed_at: Time.current)
      end

      record_push!
    end

    private

    attr_reader :push_session, :adapter

    def version
      @version ||= push_session.playlist_version
    end

    def target
      @target ||= push_session.smart_playlist.target_playlist
    end

    def authoritative_snapshot_id
      adapter.playlist_snapshot_id(target.spotify_id)
    rescue Spotify::ApiError => e
      Rails.logger.warn("Could not re-read snapshot after push #{push_session.id}: #{e.message}")
      nil
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
