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
    first_page_response = fetch_first_page(adapter, playlist)

    total_tracks = first_page_response["total"] || 0
    first_page_items = first_page_response["items"] || []
    page_size = playlist.spotify_page_size

    total_pages = (total_tracks.to_f / page_size).ceil
    total_pages = [total_pages, 1].max

    version = PlaylistVersion.create_for_sync!(playlist)

    ActiveRecord::Base.transaction do
      playlist_session.update!(
        status: :fetching_pages,
        playlist_version: version,
        total_pages: total_pages,
        completed_pages: 0,
        started_at: Time.current
      )

      process_first_page(first_page_items, version) if first_page_items.any?
    end

    enqueue_remaining_pages(playlist_session, total_pages, first_page_items)

    Rails.logger.info(
      "PlaylistSyncSetupJob: playlist=#{playlist.id} version=#{version.id} " \
      "total_tracks=#{total_tracks} pages=#{total_pages}"
    )
  end

  private

  def fetch_first_page(adapter, playlist)
    if playlist.liked_songs?
      adapter.liked_songs(limit: playlist.spotify_page_size, offset: 0)
    else
      response = adapter.playlist(playlist.spotify_id)
      response["tracks"] || { "total" => 0, "items" => [] }
    end
  end

  def process_first_page(items, version)
    tracks_by_spotify_id = Spotify::TrackUpserter.new.call(items)
    Spotify::PlaylistVersionTrackBuilder.new(version).call(items, tracks_by_spotify_id)
  end

  def enqueue_remaining_pages(playlist_session, total_pages, first_page_items)
    start_page = first_page_items.any? ? 1 : 0

    if total_pages == 1 && first_page_items.any?
      complete_single_page_playlist(playlist_session)
      return
    end

    jobs = (start_page...total_pages).map do |page_num|
      PageFetchJob.new(
        sync_session_playlist_id: playlist_session.id,
        page: page_num
      )
    end

    ActiveJob.perform_all_later(jobs) if jobs.any?
  end

  def complete_single_page_playlist(playlist_session)
    PlaylistSyncCompleter.new(playlist_session).call if playlist_session.page_completed!
  end
end
