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
    @user_id = user_id
    user = User.find(user_id)
    @result = Spotify::LibrarySyncInitializer.new(user).call

    if @result.skipped_reason
      Rails.logger.info("LibrarySyncJob: user=#{user_id} #{@result.skipped_reason}")
      return
    end

    enqueue_playlist_setup_jobs
    log_success
  end

  private

  def enqueue_playlist_setup_jobs
    jobs = @result.playlist_session_ids.map { |id| PlaylistSyncSetupJob.new(id) }
    ActiveJob.perform_all_later(jobs)
  end

  def log_success
    Rails.logger.info(
      "LibrarySyncJob: user=#{@user_id} session=#{@result.sync_session.id} " \
      "playlists=#{@result.playlist_session_ids.count}",
    )
  end
end
