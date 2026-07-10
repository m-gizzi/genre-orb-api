# frozen_string_literal: true

class ApplicationJob < ActiveJob::Base
  # Automatically retry jobs that encountered a deadlock
  # retry_on ActiveRecord::Deadlocked

  # Most jobs are safe to ignore if the underlying records are no longer available
  # discard_on ActiveJob::DeserializationError

  def self.perform_arguments(sidekiq_job)
    serialized = sidekiq_job.dig("args", 0, "arguments") || []
    ActiveJob::Arguments.deserialize(serialized)
  end
end
