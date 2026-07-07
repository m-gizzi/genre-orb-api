# frozen_string_literal: true

class PlaylistSyncCompleter
  def initialize(playlist_session)
    @playlist_session = playlist_session
  end

  def complete
    ActiveRecord::Base.transaction do
      version = @playlist_session.playlist_version
      playlist = @playlist_session.playlist

      version.update!(track_count: version.playlist_version_tracks.count)
      playlist.update!(
        current_version_id: version.id,
        last_synced_at: Time.current,
        last_synced_snapshot_id: playlist.last_seen_snapshot_id,
      )

      finalize_playlist_session(:completed)
    end
  end

  def skip
    ActiveRecord::Base.transaction do
      @playlist_session.update!(
        status: :skipped,
        completed_at: Time.current,
        total_pages: 0,
        completed_pages: 0,
      )

      finalize_sync_session_if_done
    end
  end

  private

  def finalize_playlist_session(status)
    @playlist_session.update!(status: status, completed_at: Time.current)
    finalize_sync_session_if_done
  end

  def finalize_sync_session_if_done
    sync_session = @playlist_session.sync_session
    sync_session.update!(status: :completed, completed_at: Time.current) if sync_session.all_playlists_done?
  end
end
