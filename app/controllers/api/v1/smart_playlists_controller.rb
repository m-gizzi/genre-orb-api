# frozen_string_literal: true

module Api
  module V1
    class SmartPlaylistsController < BaseController
      include SpotifyErrorRendering
      include GenreLoading

      rescue_from SmartPlaylists::Creator::MissingTargetError, with: :render_missing_target

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

      def evaluate
        smart_playlist = find_smart_playlist
        evaluator = SmartPlaylists::Evaluator.new(smart_playlist, **submitted_rules(smart_playlist))

        tracks, meta = SmartPlaylists::QueryTimeout.guard do
          pagy, page = paginate(evaluator.matches, count: evaluator.count)
          [page, evaluation_meta(pagy, evaluator)]
        end

        render_data(TrackSerializer.new(tracks, params: track_genres_for(tracks)).serializable_hash, meta: meta)
      rescue ActiveRecord::QueryCanceled
        render_validation_error(I18n.t("api.smart_playlists.evaluation_timeout"))
      end

      private

      def evaluation_meta(pagy, evaluator)
        evaluated_at = evaluator.record! if pagy.page == 1

        pagy_meta(pagy).merge(
          source_track_count: evaluator.source_track_count,
          evaluated_at: evaluated_at&.iso8601,
        )
      end

      def submitted_rules(smart_playlist)
        return {} unless smart_playlist_params.key?(:rules)

        rules = update_params[:rules]&.to_h
        validate_rules!(smart_playlist, rules)

        { rules: rules }
      end

      # `permit(rules: {})` drops a value that is not a hash, so a submitted
      # string or list arrives here as nil — a shape the tree walker would read
      # as "nothing to check" rather than as the malformed input it is.
      def validate_rules!(smart_playlist, rules)
        if rules.blank?
          smart_playlist.errors.add(:rules, I18n.t("rules.errors.group_shape"))
        else
          RuleSetValidator.new(attributes: [:rules]).validate_each(smart_playlist, :rules, rules)
          validate_rule_references!(smart_playlist, rules)
        end

        raise ActiveRecord::RecordInvalid, smart_playlist if smart_playlist.errors[:rules].any?
      end

      def validate_rule_references!(smart_playlist, rules)
        return if smart_playlist.errors[:rules].any?

        SmartPlaylists::RuleReferenceCheck.call(smart_playlist, rules).each do |message|
          smart_playlist.errors.add(:rules, message)
        end
      end

      def find_smart_playlist
        current_user.smart_playlists
                    .includes(source_playlists: :current_version, target_playlist: :current_version)
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

      def render_validation_error(message)
        render_error(message, status: :unprocessable_content, code: "validation_error")
      end
    end
  end
end
