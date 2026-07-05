# frozen_string_literal: true

module Api
  module V1
    class LibrariesController < BaseController
      def status
        session = current_user.sync_sessions.recent.first
        rate_limited = SyncRateLimitState.user_paused?(current_user.id)

        render json: {
          has_active_sync: session&.active? || false,
          current_session: session ? serialize_session(session) : nil,
          rate_limited: rate_limited,
          rate_limit_resume_at: rate_limited ? SyncRateLimitState.user_resume_at(current_user.id)&.iso8601 : nil,
          playlists_metadata_fetched_at: current_user.playlists_metadata_fetched_at&.iso8601
        }
      end

      def fetch_playlists
        unless current_user.spotify_connected?
          render json: { error: "Spotify not connected" }, status: :unprocessable_content
          return
        end

        FetchPlaylistsMetadataJob.perform_later(current_user.id)
        render json: { status: "queued" }, status: :accepted
      end

      def sync
        unless current_user.spotify_connected?
          render json: { error: "Spotify not connected" }, status: :unprocessable_content
          return
        end

        if current_user.sync_sessions.active.exists?
          render json: { error: "Sync already in progress" }, status: :conflict
          return
        end

        if current_user.playlists.sync_enabled.none?
          render json: { error: "No playlists selected for sync" }, status: :unprocessable_content
          return
        end

        LibrarySyncJob.perform_later(current_user.id)
        render json: { status: "queued" }, status: :accepted
      end

      private

      def serialize_session(session)
        {
          id: session.id,
          status: session.status,
          progress: session.progress,
          started_at: session.started_at&.iso8601,
          completed_at: session.completed_at&.iso8601,
          playlists: session.sync_session_playlists.includes(:playlist).map do |ssp|
            {
              playlist_id: ssp.playlist_id,
              playlist_name: ssp.playlist.name,
              status: ssp.status,
              page_progress: ssp.page_progress
            }
          end
        }
      end
    end
  end
end
