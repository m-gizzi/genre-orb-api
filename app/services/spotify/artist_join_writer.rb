# frozen_string_literal: true

module Spotify
  class ArtistJoinWriter
    def initialize(items, tracks_by_spotify_id:, albums_by_spotify_id:, artists_by_spotify_id:)
      @items = items
      @tracks_by_spotify_id = tracks_by_spotify_id
      @albums_by_spotify_id = albums_by_spotify_id
      @artists_by_spotify_id = artists_by_spotify_id
    end

    def call
      insert_joins(TrackArtist, items.flat_map { |item| track_rows_for(item) }, %i[track_id artist_id])
      insert_joins(AlbumArtist, items.flat_map { |item| album_rows_for(item) }, %i[album_id artist_id])
    end

    private

    attr_reader :items, :tracks_by_spotify_id, :albums_by_spotify_id, :artists_by_spotify_id

    def insert_joins(model, rows, keys)
      deduped = rows.uniq { |row| row.values_at(*keys) }.sort_by { |row| row.values_at(*keys) }
      return if deduped.empty?

      model.insert_all(deduped, unique_by: keys)
    end

    def track_rows_for(item)
      track = tracks_by_spotify_id[item.dig("track", "id")]
      return [] unless track

      artists_for(item.dig("track", "artists")).map do |artist|
        { track_id: track.id, artist_id: artist.id, created_at: Time.current, updated_at: Time.current }
      end
    end

    def album_rows_for(item)
      album = albums_by_spotify_id[item.dig("track", "album", "id")]
      return [] unless album

      artists_for(item.dig("track", "album", "artists")).map do |artist|
        { album_id: album.id, artist_id: artist.id, created_at: Time.current, updated_at: Time.current }
      end
    end

    def artists_for(sp_artists)
      Array(sp_artists).filter_map { |sp_artist| artists_by_spotify_id[sp_artist["id"]] }
    end
  end
end
