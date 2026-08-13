# frozen_string_literal: true

module Api
  module V1
    class SmartPlaylistPushesController < BaseController
      include SyncStatusRendering

      HISTORY_LIMIT = 5

      sync_outcomes(
        spotify_not_connected: { key: "api.errors.spotify_not_connected", status: :unprocessable_content },
        reauth_required: { key: "api.errors.spotify_reauth_required", status: :unprocessable_content },
        not_ready: { key: "api.smart_playlists.push_not_ready", status: :unprocessable_content },
        already_in_progress: { key: "api.smart_playlists.push_in_progress", status: :conflict },
      )

      def create
        result = SmartPlaylists::PushInitializer.new(smart_playlist).call
        return render_sync_outcome(result.outcome) unless result.started?

        render_data({ session: serialize(result.session) }, status: :accepted)
      end

      def status
        render_data(
          { active_pushes: serialize(active_pushes),
            recent_pushes: serialize(recent_pushes), }.merge(sync_meta),
        )
      end

      private

      def smart_playlist
        current_user.smart_playlists.find(params.expect(:id))
      end

      def active_pushes
        push_sessions.active.recent.to_a
      end

      def recent_pushes
        push_sessions.where.not(status: %i[pending running]).recent.limit(HISTORY_LIMIT).to_a
      end

      def push_sessions
        PushSession.where(smart_playlist: current_user.smart_playlists)
                   .includes(smart_playlist: :target_playlist)
      end

      def serialize(sessions)
        PushSessionSerializer.new(sessions).serializable_hash
      end
    end
  end
end
