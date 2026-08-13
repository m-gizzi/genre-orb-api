# frozen_string_literal: true

module Spotify
  class TrackUpserter
    def call(spotify_track_items)
      items = Spotify::PlayableTrackItems.new(spotify_track_items).call
      return {} if items.empty?

      artists_by_spotify_id = extract_and_upsert_artists(items)
      albums_by_spotify_id = extract_and_upsert_albums(items)
      tracks_by_spotify_id = upsert_tracks(items, albums_by_spotify_id)

      write_artist_joins(items, tracks_by_spotify_id, albums_by_spotify_id, artists_by_spotify_id)
      Genres::TrackGenreDeriver.new.by_track(tracks_by_spotify_id.values.map(&:id))

      tracks_by_spotify_id
    end

    private

    def write_artist_joins(items, tracks_by_spotify_id, albums_by_spotify_id, artists_by_spotify_id)
      Spotify::ArtistJoinWriter.new(
        items,
        tracks_by_spotify_id: tracks_by_spotify_id,
        albums_by_spotify_id: albums_by_spotify_id,
        artists_by_spotify_id: artists_by_spotify_id,
      ).call
    end

    def extract_and_upsert_artists(items)
      artist_data = build_artist_data(items)
      return {} if artist_data.empty?

      Artist.upsert_all(artist_data, unique_by: :spotify_id, update_only: %i[name])
      Artist.where(spotify_id: artist_data.pluck(:spotify_id)).index_by(&:spotify_id)
    end

    def build_artist_data(items)
      items
        .flat_map { |item| item.dig("track", "artists") || [] }
        .uniq { |artist| artist["id"] }
        .filter_map { |sp_artist| build_artist_record(sp_artist) }
        .sort_by { |record| record[:spotify_id] }
    end

    def build_artist_record(sp_artist)
      return nil unless sp_artist["id"]
      return nil if sp_artist["name"].blank?

      {
        spotify_id: sp_artist["id"],
        name: sp_artist["name"],
        metadata: {},
        created_at: Time.current,
        updated_at: Time.current,
      }
    end

    def extract_and_upsert_albums(items)
      album_data = build_album_data(items)
      return {} if album_data.empty?

      Album.upsert_all(album_data, unique_by: :spotify_id, update_only: %i[title artwork_url])
      Album.where(spotify_id: album_data.pluck(:spotify_id)).index_by(&:spotify_id)
    end

    def build_album_data(items)
      items
        .filter_map { |item| item.dig("track", "album") }
        .uniq { |album| album["id"] }
        .filter_map { |sp_album| build_album_record(sp_album) }
        .sort_by { |record| record[:spotify_id] }
    end

    def build_album_record(sp_album)
      return nil unless sp_album["id"]
      return nil if sp_album["name"].blank?

      {
        spotify_id: sp_album["id"],
        title: sp_album["name"],
        release_year: extract_release_year(sp_album["release_date"]),
        artwork_url: sp_album.dig("images", 0, "url"),
        total_tracks: sp_album["total_tracks"],
        created_at: Time.current,
        updated_at: Time.current,
      }
    end

    def upsert_tracks(items, albums_by_spotify_id)
      track_data = build_track_data(items, albums_by_spotify_id)
      return {} if track_data.empty?

      Track.upsert_all(
        track_data,
        unique_by: :spotify_id,
        update_only: %i[title duration_ms popularity preview_url],
      )
      Track.where(spotify_id: track_data.pluck(:spotify_id)).index_by(&:spotify_id)
    end

    def build_track_data(items, albums_by_spotify_id)
      storable, albumless = items.partition do |item|
        albums_by_spotify_id.key?(item.dig("track", "album", "id"))
      end
      log_albumless_tracks(albumless)

      storable
        .map { |item| build_track_record(item, albums_by_spotify_id) }
        .uniq { |track| track[:spotify_id] }
        .sort_by { |track| track[:spotify_id] }
    end

    def build_track_record(item, albums_by_spotify_id)
      track = item["track"]
      build_track_attributes(track, albums_by_spotify_id.fetch(track.dig("album", "id")))
    end

    def log_albumless_tracks(items)
      return if items.empty?

      Rails.logger.info("Spotify sync skipped #{items.size} track(s) whose album could not be stored")
    end

    def build_track_attributes(track, album)
      {
        spotify_id: track["id"],
        title: track["name"],
        album_id: album.id,
        duration_ms: track["duration_ms"],
        track_number: track["track_number"],
        explicit: track["explicit"] || false,
        preview_url: track["preview_url"],
        popularity: track["popularity"],
        created_at: Time.current,
        updated_at: Time.current,
      }
    end

    def extract_release_year(release_date)
      return nil unless release_date

      release_date.split("-").first&.to_i
    end
  end
end
