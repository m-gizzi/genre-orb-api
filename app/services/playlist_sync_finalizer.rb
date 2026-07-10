# frozen_string_literal: true

class PlaylistSyncFinalizer
  def initialize(playlist_session)
    @playlist_session = playlist_session
  end

  def complete!
    ActiveRecord::Base.transaction do
      version = @playlist_session.playlist_version
      playlist = @playlist_session.playlist

      version.update!(
        track_count: version.playlist_version_tracks.count,
        status: :complete,
      )
      playlist.update!(
        current_version_id: version.id,
        last_synced_at: Time.current,
        last_synced_snapshot_id: playlist.last_seen_snapshot_id,
      )

      @playlist_session.update!(status: :completed, completed_at: Time.current)
    end

    @playlist_session.sync_session.increment_completed!
    finalize
  end

  def mark_as_skipped!
    ActiveRecord::Base.transaction do
      @playlist_session.update!(
        status: :skipped,
        completed_at: Time.current,
        total_pages: 0,
        completed_pages: 0,
      )
    end

    @playlist_session.sync_session.increment_skipped!
    finalize
  end

  private

  def finalize
    sync_session = @playlist_session.sync_session
    sync_session.update!(status: :completed, completed_at: Time.current) if sync_session.all_playlists_done?
  end
end
