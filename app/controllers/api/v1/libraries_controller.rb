# frozen_string_literal: true

module Api
  module V1
    class LibrariesController < BaseController
      def status
        session = current_user.sync_sessions.recent.first

        render json: build_status_response(session)
      end

      def fetch_playlists
        return render_spotify_error unless current_user.spotify_connected?

        FetchPlaylistsMetadataJob.perform_later(current_user.id)
        render json: { status: "queued" }, status: :accepted
      end

      def sync
        error = validate_sync_request
        return render_error(error[:message], error[:status]) if error

        LibrarySyncJob.perform_later(current_user.id)
        render json: { status: "queued" }, status: :accepted
      end

      private

      def build_status_response(session)
        {
          has_active_sync: session&.active? || false,
          current_session: session ? serialize_session(session) : nil,
          playlists_metadata_fetched_at: current_user.playlists_metadata_fetched_at&.iso8601,
        }.merge(rate_limit_info)
      end

      def rate_limit_info
        rate_limited = SyncRateLimitState.user_paused?(current_user.id)
        {
          rate_limited: rate_limited,
          rate_limit_resume_at: rate_limited ? SyncRateLimitState.user_resume_at(current_user.id)&.iso8601 : nil,
        }
      end

      def validate_sync_request
        unless current_user.spotify_connected?
          return { message: "Spotify not connected", status: :unprocessable_content }
        end
        return { message: "Sync already in progress", status: :conflict } if current_user.sync_sessions.active.exists?
        return { message: "No playlists selected for sync", status: :unprocessable_content } if no_playlists_selected?

        nil
      end

      def no_playlists_selected?
        current_user.playlists.sync_enabled.none?
      end

      def render_spotify_error
        render json: { error: "Spotify not connected" }, status: :unprocessable_content
      end

      def render_error(message, status)
        render json: { error: message }, status: status
      end

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
              page_progress: ssp.page_progress,
            }
          end,
        }
      end
    end
  end
end
