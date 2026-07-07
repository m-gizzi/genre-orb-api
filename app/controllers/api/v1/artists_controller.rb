# frozen_string_literal: true

module Api
  module V1
    class ArtistsController < BaseController
      def sync_status
        session = current_user.artist_metadata_sessions.recent.first
        rate_limited = SyncRateLimitState.user_paused?(current_user.id)

        artists_total = Artist.joins(:tracks).distinct.count
        artists_synced = Artist.joins(:tracks).where.not(metadata_fetched_at: nil).distinct.count

        render json: {
          has_active_sync: session&.active? || false,
          current_session: session ? serialize_session(session) : nil,
          rate_limited: rate_limited,
          rate_limit_resume_at: rate_limited ? SyncRateLimitState.user_resume_at(current_user.id)&.iso8601 : nil,
          artists_total: artists_total,
          artists_synced: artists_synced
        }
      end

      def sync
        unless current_user.spotify_connected?
          render json: { error: "Spotify not connected" }, status: :unprocessable_content
          return
        end

        if current_user.artist_metadata_sessions.active.exists?
          render json: { error: "Artist metadata sync already in progress" }, status: :conflict
          return
        end

        sync_all = ActiveModel::Type::Boolean.new.cast(params[:sync_all])

        unless sync_all
          if Artist.where(metadata_fetched_at: nil).none?
            render json: { error: "No artists need metadata sync" }, status: :unprocessable_content
            return
          end
        end

        ArtistMetadataSyncJob.perform_later(current_user.id, sync_all: sync_all)
        render json: { status: "queued" }, status: :accepted
      end

      private

      def serialize_session(session)
        {
          id: session.id,
          status: session.status,
          progress: session.progress,
          started_at: session.started_at&.iso8601,
          completed_at: session.completed_at&.iso8601
        }
      end
    end
  end
end
