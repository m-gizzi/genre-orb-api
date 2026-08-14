# frozen_string_literal: true

module Api
  module V1
    class GenrePreferencesController < BaseController
      rescue_from Genres::PreferencesWriter::InvalidPreference, with: :render_invalid_preference

      def show
        render_data(serialize(Genres::Preferences.new(current_user)))
      end

      def update
        render_data(serialize(Genres::PreferencesWriter.new(current_user, preference_params).call))
      end

      private

      def serialize(preferences)
        GenrePreferencesSerializer.new(preferences).serializable_hash
      end

      def preference_params
        nested_params(:genre_preferences)
          .permit(blocked_genre_ids: [], sources: {})
          .to_h.deep_symbolize_keys
      end

      def render_invalid_preference(exception)
        render_error(
          I18n.t("api.genres.invalid_preference", name: exception.message),
          status: :unprocessable_content,
          code: "validation_error",
        )
      end
    end
  end
end
