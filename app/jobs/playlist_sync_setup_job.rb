# frozen_string_literal: true

class PlaylistSyncSetupJob < SpotifyJob
  sidekiq_retries_exhausted do |job, exception|
    playlist_session = SyncSessionPlaylist.find_by(id: job["args"].first)
    next unless playlist_session

    SyncFailureHandler.fail_playlist_session(
      playlist_session,
      error_message: "Setup failed after retries: #{exception.message}",
    )
  end

  def perform(sync_session_playlist_id)
    playlist_session = SyncSessionPlaylist.includes(sync_session: :user).find(sync_session_playlist_id)
    user = playlist_session.sync_session.user

    if rate_limited?(user.id)
      defer_for_rate_limit(user.id)
      return
    end

    result = run_setup(playlist_session, user)
    if result.skipped?
      log_skipped(playlist_session)
      return
    end

    enqueue_remaining_pages(playlist_session, result.remaining_pages)
    log_success(playlist_session, result)
  end

  private

  def run_setup(playlist_session, user)
    adapter = SpotifyAdapter.new(user.spotify_connection)
    Spotify::PlaylistSyncSetup.new(playlist_session, adapter: adapter).call
  end

  def log_skipped(playlist_session)
    Rails.logger.info("PlaylistSyncSetupJob: playlist=#{playlist_session.playlist.id} skipped - snapshot unchanged")
  end

  def enqueue_remaining_pages(playlist_session, remaining_pages)
    return if remaining_pages.empty?

    jobs = remaining_pages.map do |page_num|
      PageFetchJob.new(sync_session_playlist_id: playlist_session.id, page: page_num)
    end
    ActiveJob.perform_all_later(jobs)
  end

  def log_success(playlist_session, result)
    Rails.logger.info(
      "PlaylistSyncSetupJob: playlist=#{playlist_session.playlist.id} version=#{result.version.id} " \
      "pages=#{result.remaining_pages.size + 1}",
    )
  end
end
