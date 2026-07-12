# frozen_string_literal: true

module Api
  module V1
    class ArtistsController < BaseController
      SYNC_OUTCOME_RESPONSES = {
        spotify_not_connected: { key: "api.errors.spotify_not_connected", status: :unprocessable_content },
        already_in_progress: { key: "api.artists.sync_in_progress", status: :conflict },
        no_artists: { key: "api.artists.no_artists_need_sync", status: :unprocessable_content },
      }.freeze

      def index
        scope = current_user.library_artists.order("artists.name")
        scope = scope.where("artists.name ILIKE ?", like_contains(params[:search])) if params[:search].present?

        pagy, artists = paginate(scope)
        render_data(ArtistSerializer.new(artists).serializable_hash, meta: pagy_meta(pagy))
      end

      def show
        raise ActiveRecord::RecordNotFound unless current_user.library_artists.exists?(params[:id])

        artist = Artist.find(params[:id])
        albums = current_user.library_albums.where(id: artist.album_ids)
        render_data(ArtistDetailSerializer.new(artist, params: { albums: albums }).serializable_hash)
      end

      def sync_status
        @session = current_user.artist_metadata_sessions.recent.first
        render_data(build_sync_status_response)
      end

      def sync
        result = Spotify::ArtistMetadataSyncInitializer.new(current_user, sync_all: sync_all_param).call
        return render_sync_outcome(result.outcome) unless result.started?

        @session = result.session
        render_data({ status: "queued", session: serialize_session }, status: :accepted)
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
        render_error(I18n.t(response[:key]), status: response[:status])
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
