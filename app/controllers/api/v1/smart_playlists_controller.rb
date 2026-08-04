# frozen_string_literal: true

module Api
  module V1
    class SmartPlaylistsController < BaseController
      include SpotifyErrorRendering

      rescue_from SmartPlaylists::Creator::MissingTargetError, with: :render_missing_target
      rescue_from SmartPlaylists::EvaluationRecorder::NotReadyError, with: :render_not_ready
      rescue_from ActiveRecord::QueryCanceled, with: :render_evaluation_timeout

      def schema
        expires_in 0, must_revalidate: true
        render_data(Rules::FieldCatalog.to_h) if stale?(etag: Rules::FieldCatalog.digest)
      end

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

        SmartPlaylist.transaction do
          smart_playlist.assign_attributes(update_params)
          assign_sources(smart_playlist) if smart_playlist_params.key?(:source_playlist_ids)
          smart_playlist.save!
        end

        render_data(SmartPlaylistDetailSerializer.new(smart_playlist.reload).serializable_hash)
      end

      def destroy
        find_smart_playlist.destroy!
        head :no_content
      end

      def preview
        smart_playlist = find_smart_playlist
        evaluator = SmartPlaylists::Evaluator.new(smart_playlist, **submitted_rules(smart_playlist))

        pagy, tracks = SmartPlaylists::QueryTimeout.guard do
          paginate(evaluator.matches, count: evaluator.count)
        end

        render_data(
          TrackSerializer.new(tracks).serializable_hash,
          meta: pagy_meta(pagy).merge(source_track_count: evaluator.source_track_count),
        )
      end

      def evaluate
        smart_playlist = SmartPlaylists::EvaluationRecorder.new(find_smart_playlist).call
        render_data(SmartPlaylistDetailSerializer.new(smart_playlist).serializable_hash)
      end

      private

      def submitted_rules(smart_playlist)
        return {} if smart_playlist_params[:rules].blank?

        rules = update_params[:rules].to_h
        RuleSetValidator.new(attributes: [:rules]).validate_each(smart_playlist, :rules, rules)
        raise ActiveRecord::RecordInvalid, smart_playlist if smart_playlist.errors[:rules].any?

        { rules: rules }
      end

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
              target_playlist_attributes: %i[name description], },
          ],
        )
      end

      def smart_playlist_params
        @smart_playlist_params ||= nested_params(:smart_playlist)
      end

      def update_params
        smart_playlist_params.permit(:is_enabled, rules: {})
      end

      def assign_sources(smart_playlist)
        smart_playlist.source_playlist_ids = current_user.playlists.where(id: submitted_source_ids).ids
      end

      def submitted_source_ids
        raw = smart_playlist_params[:source_playlist_ids]
        raise ActionController::ParameterMissing, :source_playlist_ids unless list_of_ids?(raw)

        raw.map(&:to_i).uniq
      end

      def list_of_ids?(value)
        value.is_a?(Array) && value.all? { |id| id.is_a?(String) || id.is_a?(Integer) }
      end

      def render_missing_target
        render_validation_error(I18n.t("api.smart_playlists.target_required"))
      end

      def render_not_ready
        render_validation_error(I18n.t("api.smart_playlists.not_ready"))
      end

      def render_evaluation_timeout
        render_validation_error(I18n.t("api.smart_playlists.evaluation_timeout"))
      end

      def render_validation_error(message)
        render_error(message, status: :unprocessable_content, code: "validation_error")
      end
    end
  end
end
