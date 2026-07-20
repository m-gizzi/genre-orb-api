# frozen_string_literal: true

module Api
  module V1
    class TracksController < BaseController
      def index
        scope = Tracks::Filter.new(current_user, params).call
        pagy, tracks = paginate(scope)
        render_data(TrackSerializer.new(tracks).serializable_hash, meta: pagy_meta(pagy))
      end

      def show
        track = current_user.library_tracks.with_catalog_associations.find(params.expect(:id))
        render_data(TrackSerializer.new(track).serializable_hash)
      end
    end
  end
end
