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
        raise ActiveRecord::RecordNotFound unless current_user.library_albums.exists?(params[:id])

        album = Album.includes(:artists).find(params[:id])
        tracks = current_user.library_tracks
                             .where(album_id: album.id)
                             .with_catalog_associations
                             .order(:track_number)

        render_data(AlbumDetailSerializer.new(album, params: { tracks: tracks }).serializable_hash)
      end
    end
  end
end
