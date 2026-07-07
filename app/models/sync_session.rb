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
    total = sync_session_playlists.count
    done = sync_session_playlists.done.count
    skipped = sync_session_playlists.skipped.count
    { total: total, completed: done, skipped: skipped, percent: total.positive? ? (done * 100 / total) : 0 }
  end

  def all_playlists_done?
    sync_session_playlists.count == sync_session_playlists.done.count
  end

  def active?
    pending? || running? || paused?
  end
end
