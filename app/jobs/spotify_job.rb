# frozen_string_literal: true

class SpotifyJob < ApplicationJob
  queue_as :sync

  sidekiq_options retry: 5

  around_perform do |_job, block|
    block.call
  rescue Spotify::RateLimitError => e
    SyncRateLimitState.pause!(e.user_id, e.retry_after)
    defer_for_rate_limit(e.user_id)
  end

  discard_on(Spotify::ReauthRequiredError) do |job, error|
    job.class.abandon(job.arguments.first, error)
  end

  class << self
    def abandon(arguments, exception)
      Rails.logger.error("#{name} abandoned (#{exception.class}): #{exception.message} #{arguments.inspect}")
    end
  end

  private

  def guard_connection!(user)
    connection = user.spotify_connection
    return connection unless connection.nil? || connection.needs_reauth?

    raise Spotify::ReauthRequiredError, "Spotify must be reconnected"
  end

  def rate_limited?(user_id)
    SyncRateLimitState.wait_time_for_user(user_id).positive?
  end

  def defer_for_rate_limit(user_id)
    wait_time = SyncRateLimitState.wait_time_for_user(user_id)
    self.class.set(wait: wait_time.seconds).perform_later(*arguments)
  end
end
