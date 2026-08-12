# frozen_string_literal: true

class PlaylistSyncFinalizer
  attr_reader :playlist_session

  def initialize(playlist_session)
    @playlist_session = playlist_session
  end

  def complete!
    ActiveRecord::Base.transaction do
      complete_version!
      complete_playlist!
      playlist_session.update!(status: :completed, completed_at: Time.current)
    end

    sync_session.increment_completed!
    sync_session.reconcile!
  end

  def mark_as_skipped!(reason)
    playlist_session.update!(
      status: :skipped,
      skip_reason: reason,
      completed_at: Time.current,
      total_pages: 0,
      completed_pages: 0,
    )

    sync_session.increment_skipped!
    sync_session.reconcile!
  end

  private

  def sync_session
    playlist_session.sync_session
  end

  def complete_version!
    version = playlist_session.playlist_version
    version.update!(
      track_count: version.playlist_version_tracks.count,
      status: :complete,
    )
  end

  # A sync may only replace the version it started from. A push that finalized while
  # these pages were coming down has already installed a newer version, and this read
  # predates it — so the swap stands down, and last_synced_* is left stale on purpose
  # so the next run re-reads the playlist the push wrote.
  def complete_playlist!
    playlist = playlist_session.playlist
    claimed = Playlist.where(id: playlist.id, current_version_id: playlist_session.baseline_version_id)
                      .update_all(synced_playlist_attributes(playlist))
    return unless claimed.zero?

    log_superseded(playlist)
  end

  def synced_playlist_attributes(playlist)
    now = Time.current
    {
      current_version_id: playlist_session.playlist_version_id,
      last_synced_at: now,
      last_synced_snapshot_id: playlist.last_seen_snapshot_id,
      updated_at: now,
    }
  end

  def log_superseded(playlist)
    Rails.logger.info(
      "PlaylistSyncFinalizer: playlist=#{playlist.id} version=#{playlist_session.playlist_version_id} " \
      "superseded - current_version moved during sync",
    )
  end
end
