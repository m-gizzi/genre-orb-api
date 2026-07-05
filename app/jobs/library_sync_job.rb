# frozen_string_literal: true

class LibrarySyncJob < ApplicationJob
  queue_as :sync

  sidekiq_retries_exhausted do |job, exception|
    user_id = job["args"].first
    session = SyncSession.where(user_id: user_id).active.order(created_at: :desc).first
    next unless session

    SyncFailureHandler.fail_session(session, error_message: "Library sync failed: #{exception.message}")
  end

  def perform(user_id)
    user = User.find(user_id)
    playlists = user.playlists.sync_enabled.available

    if playlists.empty?
      Rails.logger.info("LibrarySyncJob: user=#{user_id} no playlists to sync")
      return
    end

    session = SyncSession.create!(user: user, status: :running, started_at: Time.current)

    playlist_sessions = playlists.map do |playlist|
      session.sync_session_playlists.create!(playlist: playlist, status: :pending)
    end

    jobs = playlist_sessions.map { |session| PlaylistSyncSetupJob.new(session.id) }
    ActiveJob.perform_all_later(jobs)

    Rails.logger.info("LibrarySyncJob: user=#{user_id} session=#{session.id} playlists=#{playlists.count}")
  end
end
