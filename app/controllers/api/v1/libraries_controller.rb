# frozen_string_literal: true

module Api
  module V1
    class LibrariesController < BaseController
      SYNC_OUTCOME_RESPONSES = {
        spotify_not_connected: { key: "api.errors.spotify_not_connected", status: :unprocessable_content },
        already_in_progress: { key: "api.library.sync_in_progress", status: :conflict },
        no_playlists: { key: "api.library.no_playlists_selected", status: :unprocessable_content },
      }.freeze

      def status
        @session = current_user.sync_sessions
                               .includes(sync_session_playlists: :playlist)
                               .recent
                               .first

        render json: build_status_response
      end

      def fetch_playlists
        return render_spotify_error unless current_user.spotify_connected?

        FetchPlaylistsMetadataJob.perform_later(current_user.id)
        render json: { status: "queued" }, status: :accepted
      end

      def sync
        result = Spotify::LibrarySyncInitializer.new(current_user).call
        return render_sync_outcome(result.outcome) unless result.started?

        @session = result.sync_session
        render json: { status: "queued", session: serialize_session }, status: :accepted
      end

      private

      def build_status_response
        {
          has_active_sync: @session&.active? || false,
          current_session: @session ? serialize_session : nil,
          playlists_metadata_fetched_at: current_user.playlists_metadata_fetched_at&.iso8601,
          playlists_metadata_error: current_user.playlists_metadata_error,
        }.merge(rate_limit_info)
      end

      def rate_limit_info
        rate_limited = SyncRateLimitState.user_paused?(current_user.id)
        {
          rate_limited: rate_limited,
          rate_limit_resume_at: rate_limited ? SyncRateLimitState.user_resume_at(current_user.id)&.iso8601 : nil,
        }
      end

      def render_sync_outcome(outcome)
        response = SYNC_OUTCOME_RESPONSES.fetch(outcome)
        render_error(I18n.t(response[:key]), response[:status])
      end

      def render_spotify_error
        render json: { error: I18n.t("api.errors.spotify_not_connected") }, status: :unprocessable_content
      end

      def render_error(message, status)
        render json: { error: message }, status: status
      end

      def serialize_session
        {
          id: @session.id,
          status: @session.status,
          progress: @session.progress,
          error_message: @session.error_message,
          started_at: @session.started_at&.iso8601,
          completed_at: @session.completed_at&.iso8601,
          playlists: @session.sync_session_playlists.map { |ssp| serialize_session_playlist(ssp) },
        }
      end

      def serialize_session_playlist(ssp)
        {
          playlist_id: ssp.playlist_id,
          playlist_name: ssp.playlist.name,
          status: ssp.status,
          page_progress: ssp.page_progress,
          error_message: ssp.error_message,
        }
      end
    end
  end
end
