# frozen_string_literal: true

class SyncSessionPlaylist < ApplicationRecord
  belongs_to :sync_session, inverse_of: :sync_session_playlists
  belongs_to :playlist, inverse_of: :sync_session_playlists
  belongs_to :playlist_version, optional: true

  enum :status, {
    pending: 0,
    fetching_pages: 1,
    completed: 2,
    failed: 3,
    skipped: 4
  }

  scope :done, -> { where(status: %i[completed skipped]) }

  def page_progress
    { total: total_pages, completed: completed_pages }
  end

  def page_completed!
    with_lock do
      increment!(:completed_pages)
      completed_pages >= total_pages
    end
  end
end
