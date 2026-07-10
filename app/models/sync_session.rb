# frozen_string_literal: true

class SyncSession < ApplicationRecord
  belongs_to :user, inverse_of: :sync_sessions
  has_many :sync_session_playlists, dependent: :destroy, inverse_of: :sync_session
  has_many :playlists, through: :sync_session_playlists

  enum :status, {
    pending: 0,
    running: 1,
    paused: 2,
    completed: 3,
    failed: 4,
    cancelled: 5,
  }

  scope :active, -> { where(status: %i[pending running paused]) }
  scope :recent, -> { order(created_at: :desc) }

  def progress
    done = completed_playlists + skipped_playlists
    {
      total: total_playlists,
      completed: done,
      skipped: skipped_playlists,
      percent: total_playlists.positive? ? (done * 100 / total_playlists) : 0,
    }
  end

  def all_playlists_done?
    total_playlists.positive? && (completed_playlists + skipped_playlists) >= total_playlists
  end

  def increment_completed!
    with_lock do
      increment!(:completed_playlists)
    end
  end

  def increment_skipped!
    with_lock do
      increment!(:skipped_playlists)
    end
  end

  def active?
    pending? || running? || paused?
  end
end
