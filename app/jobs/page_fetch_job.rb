# frozen_string_literal: true

class PageFetchJob < SpotifyJob
  sidekiq_retries_exhausted do |job, exception|
    args = job["args"].first
    playlist_session = SyncSessionPlaylist.find_by(id: args["sync_session_playlist_id"])
    next unless playlist_session

    SyncFailureHandler.fail_playlist_session(
      playlist_session,
      error_message: "Page #{args['page']} failed after retries: #{exception.message}"
    )
  end

  def perform(sync_session_playlist_id:, page:)
    playlist_session = SyncSessionPlaylist.includes(:playlist, :playlist_version, sync_session: :user).find(sync_session_playlist_id)
    user = playlist_session.sync_session.user

    return if defer_if_rate_limited(user.id)

    playlist = playlist_session.playlist
    version = playlist_session.playlist_version
    adapter = SpotifyAdapter.new(user.spotify_connection)

    page_size = playlist.spotify_page_size
    offset = page * page_size

    response = playlist.fetch_tracks_page(adapter, limit: page_size, offset: offset)
    items = response["items"] || []

    ActiveRecord::Base.transaction do
      tracks_by_spotify_id = Spotify::TrackUpserter.new.call(items)
      Spotify::PlaylistVersionTrackBuilder.new(version).call(items, tracks_by_spotify_id, offset: offset)

      PlaylistSyncCompleter.new(playlist_session).call if playlist_session.page_completed!
    end
  end
end
