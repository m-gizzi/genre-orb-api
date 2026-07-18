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
        scope = Artists::Filter.new(current_user, params).call

        pagy, artists = paginate(scope)
        render_data(ArtistSerializer.new(artists).serializable_hash, meta: pagy_meta(pagy))
      end

      def show
        artist = current_user.library_artists.find(params.expect(:id))
        render_data(ArtistDetailSerializer.new(artist, params: detail_params(artist)).serializable_hash)
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

      def detail_params(artist)
        albums = albums_for(artist)
        {
          albums: albums,
          saved_counts: saved_counts(albums),
          genre_ids: genre_id_lookup(artist),
        }
      end

      def albums_for(artist)
        current_user.library_albums
                    .includes(:artists)
                    .where(id: artist.album_ids)
                    .order(Album.arel_table[:release_year].asc.nulls_last)
      end

      def saved_counts(albums)
        current_user.library_tracks
                    .where(album_id: albums.map(&:id))
                    .group(:album_id)
                    .count(:id)
      end

      def genre_id_lookup(artist)
        names = (artist.metadata&.dig("genres") || []).map { |name| Genre.normalize_name(name) }
        return {} if names.empty?

        current_user.library_genres.where(name: names).pluck(:name, :id).to_h
      end

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
