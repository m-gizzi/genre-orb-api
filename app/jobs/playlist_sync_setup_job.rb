# frozen_string_literal: true

class PlaylistSyncSetupJob < SpotifyJob
  sidekiq_retries_exhausted do |job, exception|
    playlist_session = SyncSessionPlaylist.find_by(id: job["args"].first)
    next unless playlist_session

    SyncFailureHandler.fail_playlist_session(
      playlist_session,
      error_message: "Setup failed after retries: #{exception.message}"
    )
  end

  def perform(sync_session_playlist_id)
    playlist_session = SyncSessionPlaylist.includes(sync_session: :user).find(sync_session_playlist_id)
    playlist = playlist_session.playlist
    user = playlist_session.sync_session.user

    return if defer_if_rate_limited(user.id)

    adapter = SpotifyAdapter.new(user.spotify_connection)
    result = Spotify::PlaylistSyncSetup.new(playlist_session, adapter: adapter).call

    if result.skipped?
      Rails.logger.info("PlaylistSyncSetupJob: playlist=#{playlist.id} skipped - snapshot unchanged")
      return
    end

    enqueue_remaining_pages(playlist_session, result.remaining_pages)

    Rails.logger.info(
      "PlaylistSyncSetupJob: playlist=#{playlist.id} version=#{result.version.id} " \
      "pages=#{result.remaining_pages.size + 1}"
    )
  end

  private

  def enqueue_remaining_pages(playlist_session, remaining_pages)
    return if remaining_pages.empty?

    jobs = remaining_pages.map do |page_num|
      PageFetchJob.new(
        sync_session_playlist_id: playlist_session.id,
        page: page_num
      )
    end

    ActiveJob.perform_all_later(jobs)
  end
end
