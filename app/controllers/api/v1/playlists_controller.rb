# frozen_string_literal: true

module Api
  module V1
    class PlaylistsController < BaseController
      include SpotifyErrorRendering
      include GenreLoading

      def index
        scope = Playlists::Filter.new(current_user, params).call

        pagy, playlists = paginate(scope)
        render_data(PlaylistSerializer.new(playlists).serializable_hash, meta: pagy_meta(pagy))
      end

      def show
        playlist = current_user.playlists
                               .includes(:current_version, :smart_playlist_as_target)
                               .find(params.expect(:id))
        render_data(PlaylistDetailSerializer.new(playlist).serializable_hash)
      end

      def liked
        playlist = current_user.liked_songs_playlist
        render_data(playlist ? PlaylistSerializer.new(playlist).serializable_hash : nil)
      end

      def tracks
        playlist = find_playlist
        pagy, version_tracks = paginate(Playlists::TrackFilter.new(current_user, params, playlist).call)
        tracks = version_tracks.map(&:track)
        render_data(
          TrackSerializer.new(tracks, params: track_genres_for(tracks)).serializable_hash,
          meta: pagy_meta(pagy),
        )
      end

      def genres
        filter = Genres::Filter.new(current_user, params, tracks: find_playlist.tracks)

        pagy, genres = paginate(filter.call)
        render_data(
          GenreBreakdownSerializer.new(genres, params: breakdown_params(filter, genres)).serializable_hash,
          meta: pagy_meta(pagy),
        )
      end

      def create
        playlist = Spotify::PlaylistCreator.new(current_user, create_params).call
        render_data(PlaylistSerializer.new(playlist).serializable_hash, status: :created)
      end

      def update
        playlist = find_playlist
        Spotify::PlaylistDetailsPusher.new(playlist, update_params).call
        render_data(PlaylistSerializer.new(playlist).serializable_hash)
      end

      private

      def find_playlist
        current_user.playlists.find(params.expect(:id))
      end

      def breakdown_params(filter, genres)
        { blocked_genre_ids: blocked_genre_ids, track_counts: filter.track_counts_for(genres) }
      end

      def create_params
        params.expect(playlist: %i[name description])
      end

      def update_params
        params.expect(playlist: %i[name description sync_enabled])
      end
    end
  end
end
