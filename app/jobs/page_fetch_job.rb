# frozen_string_literal: true

class PageFetchJob < SpotifyJob
  sidekiq_retries_exhausted do |job, exception|
    args = job["args"].first
    playlist_session = SyncSessionPlaylist.find_by(id: args["sync_session_playlist_id"])
    next unless playlist_session

    SyncFailureHandler.fail_playlist_session(
      playlist_session,
      error_message: "Page #{args["page"]} failed after retries: #{exception.message}",
    )
  end

  def perform(sync_session_playlist_id:, page:)
    playlist_session = SyncSessionPlaylist.includes(:playlist, :playlist_version,
                                                    sync_session: :user,).find(sync_session_playlist_id)
    user = playlist_session.sync_session.user

    if rate_limited?(user.id)
      defer_for_rate_limit(user.id)
      return
    end

    adapter = SpotifyAdapter.new(user.spotify_connection)
    Spotify::PlaylistPageFetcher.new(playlist_session, page: page, adapter: adapter).call
  end
end
