# frozen_string_literal: true

module Api
  module V1
    class LibrariesController < BaseController
      include SyncStatusRendering

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

        render_data(build_status_response)
      end

      def fetch_playlists
        return render_spotify_error unless current_user.spotify_connected?

        FetchPlaylistsMetadataJob.perform_later(current_user.id)
        render_data({ status: "queued" }, status: :accepted)
      end

      def sync
        result = Spotify::LibrarySyncInitializer.new(current_user).call
        return render_sync_outcome(result.outcome) unless result.started?

        @session = result.sync_session
        render_data({ status: "queued", session: serialize_session(@session) }, status: :accepted)
      end

      private

      def build_status_response
        {
          has_active_sync: @session&.active? || false,
          current_session: @session ? serialize_session(@session) : nil,
          playlists_metadata_fetched_at: current_user.playlists_metadata_fetched_at&.iso8601,
          playlists_metadata_error: current_user.playlists_metadata_error,
        }.merge(rate_limit_info)
      end

      def render_spotify_error
        render_error(I18n.t("api.errors.spotify_not_connected"), status: :unprocessable_content)
      end

      # Library sessions carry per-playlist detail on top of the shared fields.
      def serialize_session(session)
        super.merge(
          playlists: session.sync_session_playlists.sort_by(&:id).map { |ssp| serialize_session_playlist(ssp) },
        )
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
