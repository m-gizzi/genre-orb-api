# frozen_string_literal: true

class SyncSession < ApplicationRecord
  belongs_to :user, inverse_of: :sync_sessions
  has_many :sync_session_playlists, dependent: :destroy, inverse_of: :sync_session
  has_many :playlists, through: :sync_session_playlists

  enum :status, {
    pending: 0,
    running: 1,
    completed: 2,
    failed: 3,
    completed_with_errors: 4,
  }

  scope :active, -> { where(status: %i[pending running]) }
  scope :recent, -> { order(created_at: :desc) }

  def progress
    done = completed_playlists + skipped_playlists + failed_playlists
    {
      total: total_playlists,
      completed: completed_playlists + skipped_playlists,
      skipped: skipped_playlists,
      failed: failed_playlists,
      percent: total_playlists.positive? ? (done * 100 / total_playlists) : 0,
    }
  end

  def increment_completed!
    with_lock { increment!(:completed_playlists) }
  end

  def increment_skipped!
    with_lock { increment!(:skipped_playlists) }
  end

  def increment_failed!
    with_lock { increment!(:failed_playlists) }
  end

  def reconcile!
    with_lock do
      return unless active?
      return if sync_session_playlists.where(status: %i[pending fetching_pages]).exists?

      update!(status: terminal_status, completed_at: Time.current)
    end
  end

  def active?
    pending? || running?
  end

  private

  def terminal_status
    any_failed = sync_session_playlists.where(status: :failed).exists?
    any_succeeded = sync_session_playlists.where(status: %i[completed skipped]).exists?

    if any_failed && any_succeeded
      :completed_with_errors
    elsif any_failed
      :failed
    else
      :completed
    end
  end
end
