# frozen_string_literal: true

module Api
  module V1
    class ArtistsController < BaseController
      include SyncStatusRendering

      SYNC_OUTCOME_RESPONSES = {
        spotify_not_connected: { key: "api.errors.spotify_not_connected", status: :unprocessable_content },
        already_in_progress: { key: "api.artists.sync_in_progress", status: :conflict },
        no_artists: { key: "api.artists.no_artists_need_sync", status: :unprocessable_content },
      }.freeze

      def index
        scope = Artists::Filter.new(current_user, params).call.includes(:genres)

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
        render_data({ status: "queued", session: serialize_session(@session) }, status: :accepted)
      end

      private

      def detail_params(artist)
        albums = current_user.library_albums.includes(:artists).for_artist(artist).by_release_year
        {
          albums: albums,
          saved_counts: current_user.library_tracks.counts_by_album(albums.map(&:id)),
        }
      end

      def build_sync_status_response
        {
          has_active_sync: @session&.active? || false,
          current_session: @session ? serialize_session(@session) : nil,
          artists_total: artist_counts[:total],
          artists_synced: artist_counts[:synced],
        }.merge(rate_limit_info)
      end

      def artist_counts
        @artist_counts ||= {
          total: current_user.library_artists.count,
          synced: current_user.library_artists.synced.count,
        }
      end

      def sync_all_param
        @sync_all_param ||= ActiveModel::Type::Boolean.new.cast(params[:sync_all]) || false
      end
    end
  end
end
