# frozen_string_literal: true

module Api
  module V1
    class GenresController < BaseController
      def index
        scope = Genres::Filter.new(current_user, params).call

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
