# frozen_string_literal: true

module Api
  module V1
    class ArtistsController < BaseController
      def sync_status
        session = current_user.artist_metadata_sessions.recent.first

        render json: build_sync_status_response(session)
      end

      def sync
        error = validate_sync_request
        return render_error(error[:message], error[:status]) if error

        ArtistMetadataSyncJob.perform_later(current_user.id, sync_all: sync_all_param)
        render json: { status: "queued" }, status: :accepted
      end

      private

      def build_sync_status_response(session)
        {
          has_active_sync: session&.active? || false,
          current_session: session ? serialize_session(session) : nil,
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
          total: Artist.joins(:tracks).distinct.count,
          synced: Artist.joins(:tracks).where.not(metadata_fetched_at: nil).distinct.count,
        }
      end

      def validate_sync_request
        unless current_user.spotify_connected?
          return { message: "Spotify not connected", status: :unprocessable_content }
        end
        return { message: "Artist metadata sync already in progress", status: :conflict } if sync_in_progress?
        return { message: "No artists need metadata sync", status: :unprocessable_content } if no_artists_need_sync?

        nil
      end

      def sync_in_progress?
        current_user.artist_metadata_sessions.active.exists?
      end

      def no_artists_need_sync?
        !sync_all_param && Artist.where(metadata_fetched_at: nil).none?
      end

      def sync_all_param
        @sync_all_param ||= ActiveModel::Type::Boolean.new.cast(params[:sync_all])
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
        }
      end
    end
  end
end
