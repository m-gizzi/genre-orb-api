# frozen_string_literal: true

module Api
  module V1
    class SmartPlaylistsController < BaseController
      include SpotifyErrorRendering

      rescue_from SmartPlaylists::Creator::MissingTargetError, with: :render_missing_target

      def index
        scope = SmartPlaylists::Filter.new(current_user, params).call

        pagy, smart_playlists = paginate(scope)
        render_data(SmartPlaylistSerializer.new(smart_playlists).serializable_hash, meta: pagy_meta(pagy))
      end

      def show
        render_data(SmartPlaylistDetailSerializer.new(find_smart_playlist).serializable_hash)
      end

      def create
        smart_playlist = SmartPlaylists::Creator.new(current_user, create_params).call
        render_data(SmartPlaylistDetailSerializer.new(smart_playlist).serializable_hash, status: :created)
      end

      def update
        smart_playlist = find_smart_playlist
        smart_playlist.assign_attributes(update_params)
        assign_sources(smart_playlist) if params[:smart_playlist].key?(:source_playlist_ids)
        smart_playlist.save!

        render_data(SmartPlaylistDetailSerializer.new(smart_playlist.reload).serializable_hash)
      end

      def destroy
        find_smart_playlist.destroy!
        head :no_content
      end

      private

      def find_smart_playlist
        current_user.smart_playlists
                    .includes(:source_playlists, target_playlist: :current_version)
                    .find(params.expect(:id))
      end

      def create_params
        params.expect(
          smart_playlist: [
            :target_playlist_id,
            { source_playlist_ids: [],
              target_playlist_attributes: %i[name description is_public], },
          ],
        )
      end

      def update_params
        params.fetch(:smart_playlist, {}).permit(:is_enabled, rules: {})
      end

      def assign_sources(smart_playlist)
        ids = Array(params[:smart_playlist][:source_playlist_ids]).map(&:to_i).uniq
        smart_playlist.source_playlist_ids = current_user.playlists.where(id: ids).ids
      end

      def render_missing_target
        render_error(
          I18n.t("api.smart_playlists.target_required"),
          status: :unprocessable_content,
          code: "validation_error",
        )
      end
    end
  end
end
