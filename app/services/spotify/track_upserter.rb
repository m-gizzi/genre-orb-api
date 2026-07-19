# frozen_string_literal: true

module Spotify
  class TrackUpserter
    def call(spotify_track_items)
      return {} if spotify_track_items.empty?

      artists_by_spotify_id = extract_and_upsert_artists(spotify_track_items)
      albums_by_spotify_id = extract_and_upsert_albums(spotify_track_items)
      tracks_by_spotify_id = upsert_tracks(spotify_track_items, albums_by_spotify_id)

      create_track_artist_joins(spotify_track_items, tracks_by_spotify_id, artists_by_spotify_id)
      create_album_artist_joins(spotify_track_items, albums_by_spotify_id, artists_by_spotify_id)
      propagate_known_artist_genres(spotify_track_items, tracks_by_spotify_id, artists_by_spotify_id)

      tracks_by_spotify_id
    end

    private

    def propagate_known_artist_genres(items, tracks_by_spotify_id, artists_by_spotify_id)
      pairs = items.flat_map do |item|
        track = tracks_by_spotify_id[item.dig("track", "id")]
        next [] unless track

        genre_pairs_for_track(track, item, artists_by_spotify_id)
      end
      Spotify::TrackGenrePropagator.new.call(pairs)
    end

    def genre_pairs_for_track(track, item, artists_by_spotify_id)
      (item.dig("track", "artists") || []).flat_map do |sp_artist|
        artist = artists_by_spotify_id[sp_artist["id"]]
        genres = artist&.metadata&.dig("genres") || []
        genres.map { |genre_name| { track_id: track.id, genre_name: genre_name } }
      end
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
      items
        .filter_map { |item| build_track_record(item, albums_by_spotify_id) }
        .uniq { |track| track[:spotify_id] }
        .sort_by { |track| track[:spotify_id] }
    end

    def build_track_record(item, albums_by_spotify_id)
      track = item["track"]
      return nil unless track && track["id"]
      return nil if unusable_track?(track)

      album = albums_by_spotify_id[track.dig("album", "id")]
      return nil unless album

      build_track_attributes(track, album)
    end

    def unusable_track?(track)
      track["name"].blank? || track["duration_ms"].to_i.zero?
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

    def create_track_artist_joins(items, tracks_by_spotify_id, artists_by_spotify_id)
      join_records = build_track_artist_joins(items, tracks_by_spotify_id, artists_by_spotify_id)
      return if join_records.empty?

      TrackArtist.upsert_all(join_records, unique_by: %i[track_id artist_id])
    end

    def build_track_artist_joins(items, tracks_by_spotify_id, artists_by_spotify_id)
      records = items.flat_map do |item|
        build_track_artist_records(item, tracks_by_spotify_id, artists_by_spotify_id)
      end
      records.uniq { |record| [record[:track_id], record[:artist_id]] }
    end

    def build_track_artist_records(item, tracks_by_spotify_id, artists_by_spotify_id)
      track = tracks_by_spotify_id[item.dig("track", "id")]
      return [] unless track

      (item.dig("track", "artists") || []).filter_map do |sp_artist|
        artist = artists_by_spotify_id[sp_artist["id"]]
        next unless artist

        { track_id: track.id, artist_id: artist.id, created_at: Time.current, updated_at: Time.current }
      end
    end

    def create_album_artist_joins(items, albums_by_spotify_id, artists_by_spotify_id)
      join_records = build_album_artist_joins(items, albums_by_spotify_id, artists_by_spotify_id)
      return if join_records.empty?

      AlbumArtist.upsert_all(join_records, unique_by: %i[album_id artist_id])
    end

    def build_album_artist_joins(items, albums_by_spotify_id, artists_by_spotify_id)
      records = items.flat_map do |item|
        build_album_artist_records(item, albums_by_spotify_id, artists_by_spotify_id)
      end
      records.uniq { |record| [record[:album_id], record[:artist_id]] }
    end

    def build_album_artist_records(item, albums_by_spotify_id, artists_by_spotify_id)
      album = albums_by_spotify_id[item.dig("track", "album", "id")]
      return [] unless album

      (item.dig("track", "album", "artists") || []).filter_map do |sp_artist|
        artist = artists_by_spotify_id[sp_artist["id"]]
        next unless artist

        { album_id: album.id, artist_id: artist.id, created_at: Time.current, updated_at: Time.current }
      end
    end

    def extract_release_year(release_date)
      return nil unless release_date

      release_date.split("-").first&.to_i
    end
  end
end
