# frozen_string_literal: true

class SyncSessionPlaylist < ApplicationRecord
  include FanInCounter

  belongs_to :sync_session, inverse_of: :sync_session_playlists
  belongs_to :playlist, inverse_of: :sync_session_playlists
  belongs_to :playlist_version, optional: true
  belongs_to :baseline_version, class_name: "PlaylistVersion", optional: true

  enum :status, {
    pending: 0,
    fetching_pages: 1,
    completed: 2,
    failed: 3,
    skipped: 4,
  }

  enum :skip_reason, {
    snapshot_unchanged: 0,
    push_in_flight: 1,
  }, prefix: true

  def page_progress
    { total: total_pages, completed: completed_pages }
  end

  def page_completed!
    advance_counter!(:completed_pages, :total_pages)
  end
end
