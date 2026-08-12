# frozen_string_literal: true

module Api
  module V1
    class LibrariesController < BaseController
      include SyncStatusRendering

      sync_outcomes(
        spotify_not_connected: { key: "api.errors.spotify_not_connected", status: :unprocessable_content },
        already_in_progress: { key: "api.library.sync_in_progress", status: :conflict },
        no_playlists: { key: "api.library.no_playlists_selected", status: :unprocessable_content },
      )

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

        render_data({ session: serialize_session(result.sync_session) }, status: :accepted)
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

      def serialize_session(session)
        SyncSessionSerializer.new(session).serializable_hash
      end
    end
  end
end
