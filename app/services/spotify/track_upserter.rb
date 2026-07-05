# frozen_string_literal: true

module Spotify
  class TrackUpserter
    def call(spotify_track_items)
      return {} if spotify_track_items.empty?

      artists = extract_and_upsert_artists(spotify_track_items)
      albums = extract_and_upsert_albums(spotify_track_items, artists)
      tracks = upsert_tracks(spotify_track_items, albums)

      create_track_artist_joins(spotify_track_items, tracks, artists)
      create_album_artist_joins(spotify_track_items, albums, artists)

      tracks
    end

    private

    def extract_and_upsert_artists(items)
      artist_data = items
        .flat_map { |item| item.dig("track", "artists") || [] }
        .uniq { |a| a["id"] }
        .filter_map do |sp_artist|
          next unless sp_artist["id"]

          {
            spotify_id: sp_artist["id"],
            name: sp_artist["name"],
            metadata: {},
            created_at: Time.current,
            updated_at: Time.current
          }
        end
        .sort_by { |a| a[:spotify_id] }

      return {} if artist_data.empty?

      Artist.upsert_all(artist_data, unique_by: :spotify_id, update_only: %i[name])
      Artist.where(spotify_id: artist_data.pluck(:spotify_id)).index_by(&:spotify_id)
    end

    def extract_and_upsert_albums(items, artists_by_spotify_id)
      album_data = items
        .map { |item| item.dig("track", "album") }
        .compact
        .uniq { |a| a["id"] }
        .filter_map do |sp_album|
          next unless sp_album["id"]

          {
            spotify_id: sp_album["id"],
            title: sp_album["name"],
            release_year: extract_release_year(sp_album["release_date"]),
            artwork_url: sp_album.dig("images", 0, "url"),
            total_tracks: sp_album["total_tracks"],
            created_at: Time.current,
            updated_at: Time.current
          }
        end
        .sort_by { |a| a[:spotify_id] }

      return {} if album_data.empty?

      Album.upsert_all(album_data, unique_by: :spotify_id, update_only: %i[title artwork_url])
      Album.where(spotify_id: album_data.pluck(:spotify_id)).index_by(&:spotify_id)
    end

    def upsert_tracks(items, albums_by_spotify_id)
      track_data = items.filter_map do |item|
        track = item["track"]
        next unless track && track["id"]

        album = albums_by_spotify_id[track.dig("album", "id")]
        next unless album

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
          updated_at: Time.current
        }
      end.uniq { |t| t[:spotify_id] }
         .sort_by { |t| t[:spotify_id] }

      return {} if track_data.empty?

      Track.upsert_all(
        track_data,
        unique_by: :spotify_id,
        update_only: %i[title duration_ms popularity preview_url]
      )
      Track.where(spotify_id: track_data.pluck(:spotify_id)).index_by(&:spotify_id)
    end

    def create_track_artist_joins(items, tracks_by_spotify_id, artists_by_spotify_id)
      join_records = items.flat_map do |item|
        track_spotify_id = item.dig("track", "id")
        track = tracks_by_spotify_id[track_spotify_id]
        next [] unless track

        (item.dig("track", "artists") || []).filter_map do |sp_artist|
          artist = artists_by_spotify_id[sp_artist["id"]]
          next unless artist

          {
            track_id: track.id,
            artist_id: artist.id,
            created_at: Time.current,
            updated_at: Time.current
          }
        end
      end

      return if join_records.empty?

      TrackArtist.upsert_all(
        join_records.uniq { |r| [r[:track_id], r[:artist_id]] },
        unique_by: %i[track_id artist_id]
      )
    end

    def create_album_artist_joins(items, albums_by_spotify_id, artists_by_spotify_id)
      join_records = items.flat_map do |item|
        album_spotify_id = item.dig("track", "album", "id")
        album = albums_by_spotify_id[album_spotify_id]
        next [] unless album

        (item.dig("track", "album", "artists") || []).filter_map do |sp_artist|
          artist = artists_by_spotify_id[sp_artist["id"]]
          next unless artist

          {
            album_id: album.id,
            artist_id: artist.id,
            created_at: Time.current,
            updated_at: Time.current
          }
        end
      end

      return if join_records.empty?

      AlbumArtist.upsert_all(
        join_records.uniq { |r| [r[:album_id], r[:artist_id]] },
        unique_by: %i[album_id artist_id]
      )
    end

    def extract_release_year(release_date)
      return nil unless release_date

      release_date.split("-").first&.to_i
    end
  end
end
