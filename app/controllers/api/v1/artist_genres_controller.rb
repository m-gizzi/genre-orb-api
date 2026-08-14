# frozen_string_literal: true

module Api
  module V1
    class ArtistGenresController < BaseController
      include GenreOverriding

      private

      def subject
        @subject ||= current_user.library_artists.find(params.expect(:artist_id))
      end

      def render_genres
        render_data(SourcedGenres.for(subject, artist_genres_for([subject])))
      end
    end
  end
end
