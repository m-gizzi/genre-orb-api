# frozen_string_literal: true

class PushSession < ApplicationRecord
  belongs_to :smart_playlist, inverse_of: :push_sessions
  belongs_to :playlist_version, optional: true

  enum :status, {
    pending: 0,
    running: 1,
    completed: 2,
    failed: 3,
  }

  enum :strategy, {
    diff: 0,
    replace: 1,
  }, prefix: true

  scope :active, -> { where(status: %i[pending running]) }
  scope :recent, -> { order(created_at: :desc) }

  delegate :name, :user, :user_id, to: :smart_playlist

  def progress
    total = total_remove_batches + total_add_batches
    return { total: 0, completed: 0, percent: 100 } if total.zero?

    completed = completed_remove_batches + completed_add_batches
    { total: total, completed: completed, percent: (completed * 100 / total) }
  end

  def remove_batch_completed!(snapshot_id)
    batch_completed!(:completed_remove_batches, :total_remove_batches, snapshot_id)
  end

  def add_batch_completed!(snapshot_id)
    batch_completed!(:completed_add_batches, :total_add_batches, snapshot_id)
  end

  def active?
    pending? || running?
  end

  private

  def batch_completed!(completed_column, total_column, snapshot_id)
    with_lock do
      self[completed_column] += 1
      self.spotify_snapshot_id = snapshot_id if snapshot_id
      save!
      self[completed_column] >= self[total_column]
    end
  end
end
