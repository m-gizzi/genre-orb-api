# frozen_string_literal: true

module Api
  module V1
    class ArtistsController < BaseController
      SYNC_OUTCOME_RESPONSES = {
        spotify_not_connected: { key: "api.errors.spotify_not_connected", status: :unprocessable_content },
        already_in_progress: { key: "api.artists.sync_in_progress", status: :conflict },
        no_artists: { key: "api.artists.no_artists_need_sync", status: :unprocessable_content },
      }.freeze

      def sync_status
        @session = current_user.artist_metadata_sessions.recent.first

        render json: build_sync_status_response
      end

      def sync
        result = Spotify::ArtistMetadataSyncInitializer.new(current_user, sync_all: sync_all_param).call
        return render_sync_outcome(result.outcome) unless result.started?

        @session = result.session
        render json: { status: "queued", session: serialize_session }, status: :accepted
      end

      private

      def build_sync_status_response
        {
          has_active_sync: @session&.active? || false,
          current_session: @session ? serialize_session : nil,
          artists_total: artist_counts[:total],
          artists_synced: artist_counts[:synced],
        }.merge(rate_limit_info)
      end

      def rate_limit_info
        rate_limited = SyncRateLimitState.user_paused?(current_user.id)
        {
          rate_limited: rate_limited,
          rate_limit_resume_at: rate_limited ? SyncRateLimitState.user_resume_at(current_user.id)&.iso8601 : nil,
        }
      end

      def artist_counts
        @artist_counts ||= {
          total: current_user.library_artists.count,
          synced: current_user.library_artists.where.not(metadata_fetched_at: nil).count,
        }
      end

      def sync_all_param
        @sync_all_param ||= ActiveModel::Type::Boolean.new.cast(params[:sync_all]) || false
      end

      def render_sync_outcome(outcome)
        response = SYNC_OUTCOME_RESPONSES.fetch(outcome)
        render_error(I18n.t(response[:key]), response[:status])
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
        }
      end
    end
  end
end
