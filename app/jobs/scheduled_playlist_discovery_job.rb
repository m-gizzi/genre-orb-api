# frozen_string_literal: true

class ScheduledPlaylistDiscoveryJob < SpotifyJob
  sidekiq_retries_exhausted do |job, exception|
    abandon(perform_arguments(job).first, exception)
  end

  def self.abandon(arguments, exception)
    Rails.logger.error("ScheduledPlaylistDiscoveryJob abandoned (#{exception.class}): #{exception.message}")
    ScheduledRun.find_by(id: (arguments || {})[:scheduled_run_id])&.discovery_completed!
  end

  def perform(scheduled_run_id:, user_id:)
    if rate_limited?(user_id)
      defer_for_rate_limit(user_id)
      return
    end

    user = User.find(user_id)
    guard_connection!(user)
    Spotify::PlaylistMetadataFetcher.new(user).call

    ScheduledRun.find(scheduled_run_id).discovery_completed!
  end
end
