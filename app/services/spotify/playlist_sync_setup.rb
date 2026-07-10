# frozen_string_literal: true

module Spotify
  class PlaylistSyncSetup
    Result = Struct.new(:skipped?, :version, :remaining_pages, keyword_init: true)

    def initialize(playlist_session, adapter:)
      @playlist_session = playlist_session
      @playlist = playlist_session.playlist
      @adapter = adapter
      @strategy = PlaylistSyncStrategy.new(@playlist)
    end

    def call
      first_page_response, current_snapshot_id = fetch_first_page_with_snapshot
      return skip_unchanged if @strategy.snapshot_unchanged?(current_snapshot_id)

      process_sync(first_page_response)
    end

    private

    def skip_unchanged
      PlaylistSyncFinalizer.new(@playlist_session).mark_as_skipped!
      Result.new(skipped?: true)
    end

    def process_sync(first_page_response)
      first_page_items = first_page_response["items"] || []
      @total_pages = calculate_total_pages(first_page_response["total"] || 0)
      @version = PlaylistVersion.create_for_sync!(@playlist)

      persist_first_page(first_page_items)
      remaining_pages = calculate_remaining_pages(first_page_items)
      complete_if_single_page(remaining_pages)

      Result.new(skipped?: false, version: @version, remaining_pages: remaining_pages)
    end

    def calculate_total_pages(total_tracks)
      pages = (total_tracks.to_f / @strategy.page_size).ceil
      [pages, 1].max
    end

    def persist_first_page(first_page_items)
      ActiveRecord::Base.transaction do
        update_playlist_session(first_page_items)
        process_first_page_items(first_page_items) if first_page_items.any?
      end
    end

    def fetch_first_page_with_snapshot
      return fetch_liked_songs if @playlist.liked_songs?

      fetch_regular_playlist
    end

    def fetch_liked_songs
      response = @adapter.liked_songs(limit: @strategy.page_size, offset: 0)
      [response, nil]
    end

    def fetch_regular_playlist
      playlist_response = @adapter.playlist(@playlist.spotify_id)
      current_snapshot_id = playlist_response["snapshot_id"]
      @playlist.update!(last_seen_snapshot_id: current_snapshot_id)
      first_page = playlist_response["tracks"] || { "total" => 0, "items" => [] }
      [first_page, current_snapshot_id]
    end

    def update_playlist_session(first_page_items)
      initial_completed = first_page_items.any? ? 1 : 0
      @playlist_session.update!(
        status: :fetching_pages,
        playlist_version: @version,
        total_pages: @total_pages,
        completed_pages: initial_completed,
        started_at: Time.current,
      )
    end

    def process_first_page_items(first_page_items)
      tracks_by_spotify_id = Spotify::TrackUpserter.new.call(first_page_items)
      Spotify::PlaylistVersionTrackBuilder.new(@version).call(first_page_items, tracks_by_spotify_id)
    end

    def calculate_remaining_pages(first_page_items)
      has_items = first_page_items.any?
      start_page = has_items ? 1 : 0
      return [] if @total_pages == 1 && has_items

      (start_page...@total_pages).to_a
    end

    def complete_if_single_page(remaining_pages)
      return unless remaining_pages.empty? && @playlist_session.page_completed!

      PlaylistSyncFinalizer.new(@playlist_session).complete!
    end
  end
end
