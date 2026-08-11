# frozen_string_literal: true

class PushSession < ApplicationRecord
  include Sessionable

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

  delegate :name, :user, :user_id, to: :smart_playlist

  def progress
    total = total_remove_batches + total_add_batches
    return { total: 0, completed: 0, percent: 0 } if total.zero?

    completed = completed_remove_batches + completed_add_batches
    { total: total, completed: completed, percent: (completed * 100 / total) }
  end
end
