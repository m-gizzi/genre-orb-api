# frozen_string_literal: true

module Api
  module V1
    class TrackGenresController < BaseController
      include GenreOverriding

      private

      def subject
        @subject ||= current_user.library_tracks.find(params.expect(:track_id))
      end

      def render_genres
        render_data(SourcedGenres.for(subject, track_genres_for([subject])))
      end
    end
  end
end
