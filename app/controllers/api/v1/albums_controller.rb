# frozen_string_literal: true

module Api
  module V1
    class AlbumsController < BaseController
      def index
        scope = Albums::Filter.new(current_user, params).call

        pagy, albums = paginate(scope)
        render_data(
          AlbumSerializer.new(albums, params: { saved_counts: saved_counts(albums) }).serializable_hash,
          meta: pagy_meta(pagy),
        )
      end

      def show
        album = current_user.library_albums.includes(:artists).find(params.expect(:id))
        tracks = library_tracks_for(album)
        render_data(
          AlbumDetailSerializer.new(
            album,
            params: { tracks: tracks, saved_counts: { album.id => tracks.size } },
          ).serializable_hash,
        )
      end

      private

      def library_tracks_for(album)
        current_user.library_tracks
                    .where(album_id: album.id)
                    .with_catalog_associations
                    .order(:track_number)
      end

      def saved_counts(albums)
        current_user.library_tracks
                    .where(album_id: albums.map(&:id))
                    .group(:album_id)
                    .count(:id)
      end
    end
  end
end
