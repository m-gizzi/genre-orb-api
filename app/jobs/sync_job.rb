# frozen_string_literal: true

class SyncJob < ApplicationJob
  queue_as :sync

  retry_on SpotifyAdapter::RateLimitError, wait: ->(executions, exception) {
    exception.retry_after.seconds
  }, attempts: 10

  retry_on SpotifyAdapter::ApiError, wait: :polynomially_longer, attempts: 5

  retry_on ActiveRecord::Deadlocked, wait: ->(executions, _exception) {
    (0.5 * (2**executions)) + rand(0.0..0.5)
  }, attempts: 5

  around_perform do |_job, block|
    block.call
  rescue SpotifyAdapter::RateLimitError => e
    SyncRateLimitState.pause_user!(e.user_id, e.retry_after) if e.user_id
    raise
  end

  private

  def check_rate_limit(user_id)
    SyncRateLimitState.wait_time_for_user(user_id)
  end
end
