# frozen_string_literal: true

module Api
  module V1
    class AlbumsController < BaseController
      include GenreLoading

      def index
        scope = Albums::Filter.new(current_user, params).call

        pagy, albums = paginate(scope)
        saved_counts = current_user.library_tracks.counts_by_album(albums.map(&:id))
        render_data(
          AlbumSerializer.new(albums, params: { saved_counts: saved_counts }).serializable_hash,
          meta: pagy_meta(pagy),
        )
      end

      def show
        album = current_user.library_albums.includes(:artists).find(params.expect(:id))
        render_data(AlbumDetailSerializer.new(album, params: detail_params(album)).serializable_hash)
      end

      private

      def detail_params(album)
        tracks = current_user.library_tracks.for_album(album).with_catalog_associations.order(:track_number).load
        { tracks: tracks, saved_counts: { album.id => tracks.size } }.merge(track_genres_for(tracks))
      end
    end
  end
end
