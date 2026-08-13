# frozen_string_literal: true

class ArtistMetadataSession < ApplicationRecord
  include Sessionable

  belongs_to :user, inverse_of: :artist_metadata_sessions, optional: true
  belongs_to :scheduled_run, inverse_of: :artist_metadata_sessions, optional: true

  scope :global, -> { where(user_id: nil) }

  enum :status, {
    pending: 0,
    running: 1,
    completed: 2,
    failed: 3,
  }

  def progress
    return { total: 0, completed: 0, percent: 100 } if total_batches.zero?

    { total: total_batches, completed: completed_batches, percent: (completed_batches * 100 / total_batches) }
  end

  def batch_completed!
    advance_counter!(:completed_batches, :total_batches)
  end
end
