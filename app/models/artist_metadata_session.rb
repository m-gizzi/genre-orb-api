# frozen_string_literal: true

class ArtistMetadataSession < ApplicationRecord
  belongs_to :user, inverse_of: :artist_metadata_sessions

  enum :status, {
    pending: 0,
    running: 1,
    completed: 2,
    failed: 3,
  }

  scope :active, -> { where(status: %i[pending running]) }
  scope :recent, -> { order(created_at: :desc) }

  def progress
    return { total: 0, completed: 0, percent: 100 } if total_batches.zero?

    { total: total_batches, completed: completed_batches, percent: (completed_batches * 100 / total_batches) }
  end

  def batch_completed!
    with_lock do
      increment!(:completed_batches)
      completed_batches >= total_batches
    end
  end

  def active?
    pending? || running?
  end
end
