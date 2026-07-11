# frozen_string_literal: true

class SpotifyJob < ApplicationJob
  queue_as :sync

  sidekiq_options retry: 5

  around_perform do |_job, block|
    block.call
  rescue SpotifyAdapter::RateLimitError => e
    raise unless e.user_id

    SyncRateLimitState.pause_user!(e.user_id, e.retry_after)
    defer_for_rate_limit(e.user_id)
  end

  private

  def rate_limited?(user_id)
    SyncRateLimitState.wait_time_for_user(user_id).positive?
  end

  def defer_for_rate_limit(user_id)
    wait_time = SyncRateLimitState.wait_time_for_user(user_id)
    self.class.set(wait: wait_time.seconds).perform_later(*arguments)
  end
end
