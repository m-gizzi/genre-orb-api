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

    playlist_session.sync_session.increment_completed!
    finalize
  end

  def mark_as_skipped!
    ActiveRecord::Base.transaction do
      playlist_session.update!(
        status: :skipped,
        completed_at: Time.current,
        total_pages: 0,
        completed_pages: 0,
      )
    end

    playlist_session.sync_session.increment_skipped!
    finalize
  end

  private

  def complete_version!
    version = playlist_session.playlist_version
    version.update!(track_count: version.playlist_version_tracks.count, status: :complete)
  end

  def complete_playlist!
    playlist = playlist_session.playlist
    playlist.update!(
      current_version_id: playlist_session.playlist_version_id,
      last_synced_at: Time.current,
      last_synced_snapshot_id: playlist.last_seen_snapshot_id,
    )
  end

  def finalize
    sync_session = playlist_session.sync_session
    sync_session.update!(status: :completed, completed_at: Time.current) if sync_session.all_playlists_done?
  end
end
