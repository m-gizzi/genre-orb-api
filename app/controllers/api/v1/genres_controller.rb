# frozen_string_literal: true

module Api
  module V1
    class GenresController < BaseController
      def index
        scope = current_user.library_genres.order("genres.name")
        scope = scope.where("genres.name ILIKE ?", like_contains(params[:search])) if params[:search].present?

        pagy, genres = paginate(scope)
        render_data(GenreSerializer.new(genres).serializable_hash, meta: pagy_meta(pagy))
      end

      def show
        genre = current_user.library_genres.find(params.expect(:id))
        render_data(GenreSerializer.new(genre).serializable_hash)
      end
    end
  end
end
