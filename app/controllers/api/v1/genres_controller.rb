# frozen_string_literal: true

module Api
  module V1
    class GenresController < BaseController
      def index
        scope = Genres::Filter.new(current_user, params).call

        pagy, genres = paginate(scope)
        render_data(serialize(genres), meta: pagy_meta(pagy))
      end

      def show
        genre = current_user.library_genres(unblocked_scope).find(params.expect(:id))
        render_data(serialize(genre))
      end

      private

      def serialize(genres)
        GenreSerializer.new(genres, params: { blocked_genre_ids: blocked_genre_ids }).serializable_hash
      end

      def unblocked_scope
        Genres::EffectiveScope.new(current_user, apply_blocklist: false)
      end

      def blocked_genre_ids
        @blocked_genre_ids ||= current_user.blocked_genres.pluck(:genre_id)
      end
    end
  end
end
