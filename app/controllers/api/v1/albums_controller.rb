# frozen_string_literal: true

module Api
  module V1
    class AlbumsController < BaseController
      def index
        scope = current_user.library_albums.includes(:artists).order("albums.title")
        scope = scope.where("albums.title ILIKE ?", like_contains(params[:search])) if params[:search].present?

        pagy, albums = paginate(scope)
        render_data(AlbumSerializer.new(albums).serializable_hash, meta: pagy_meta(pagy))
      end

      def show
        album = current_user.library_albums.includes(:artists).find(params.expect(:id))
        render_data(AlbumDetailSerializer.new(album, params: { tracks: library_tracks_for(album) }).serializable_hash)
      end

      private

      def library_tracks_for(album)
        current_user.library_tracks
                    .where(album_id: album.id)
                    .with_catalog_associations
                    .order(:track_number)
      end
    end
  end
end
