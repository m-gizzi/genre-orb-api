# frozen_string_literal: true

module Spotify
  class ArtistMetadataUpserter
    attr_reader :artists_data

    def initialize(spotify_response)
      @artists_data = spotify_response["artists"] || []
    end

    def call
      return if artists_data.empty?

      update_artists
      propagate_genres_to_tracks
    end

    private

    def update_artists
      updates = build_artist_updates
      return if updates.empty?

      Artist.upsert_all(
        updates,
        unique_by: :spotify_id,
        update_only: %i[name image_url metadata metadata_fetched_at],
      )
    end

    def build_artist_updates
      artists_data
        .filter_map { |sp_artist| build_artist_update(sp_artist) }
        .sort_by { |update| update[:spotify_id] }
    end

    def build_artist_update(sp_artist)
      return nil unless sp_artist && sp_artist["id"]

      {
        spotify_id: sp_artist["id"],
        name: sp_artist["name"],
        image_url: sp_artist.dig("images", 0, "url"),
        metadata: build_metadata(sp_artist),
        metadata_fetched_at: Time.current,
        updated_at: Time.current,
      }
    end

    def build_metadata(sp_artist)
      {
        "genres" => sp_artist["genres"] || [],
        "followers" => sp_artist.dig("followers", "total"),
        "popularity" => sp_artist["popularity"],
      }
    end

    def propagate_genres_to_tracks
      spotify_ids = artists_data.filter_map { |artist_data| artist_data&.dig("id") }
      return if spotify_ids.empty?

      artists = Artist.where(spotify_id: spotify_ids).includes(:tracks)
      genre_names, track_genre_pairs = collect_genre_data(artists)
      return if genre_names.empty?

      upsert_genres(genre_names)
      upsert_track_genres(genre_names, track_genre_pairs)
    end

    def collect_genre_data(artists)
      genre_names = Set.new
      track_genre_pairs = []

      artists.each do |artist|
        collect_artist_genres(artist, genre_names, track_genre_pairs)
      end

      [genre_names, track_genre_pairs]
    end

    def collect_artist_genres(artist, genre_names, track_genre_pairs)
      genres = artist.metadata&.dig("genres") || []
      return if genres.empty?

      genres.each { |genre| genre_names.add(Genre.normalize_name(genre)) }
      collect_track_genres(artist.tracks, genres, track_genre_pairs)
    end

    def collect_track_genres(tracks, genres, track_genre_pairs)
      tracks.each do |track|
        genres.each do |genre_name|
          normalized = Genre.normalize_name(genre_name)
          track_genre_pairs << { track_id: track.id, genre_name: normalized } if normalized
        end
      end
    end

    def upsert_genres(genre_names)
      genre_records = genre_names.compact.map do |name|
        { name: name, created_at: Time.current, updated_at: Time.current }
      end

      Genre.upsert_all(genre_records, unique_by: :name) if genre_records.any?
    end

    def upsert_track_genres(genre_names, track_genre_pairs)
      return if track_genre_pairs.empty?

      genres_by_name = Genre.where(name: genre_names.to_a).index_by(&:name)
      track_genre_records = build_track_genre_records(track_genre_pairs, genres_by_name)
      return if track_genre_records.empty?

      TrackGenre.upsert_all(track_genre_records, unique_by: %i[track_id genre_id])
    end

    def build_track_genre_records(track_genre_pairs, genres_by_name)
      track_genre_pairs
        .filter_map { |pair| build_track_genre_record(pair, genres_by_name) }
        .uniq { |record| [record[:track_id], record[:genre_id]] }
    end

    def build_track_genre_record(pair, genres_by_name)
      genre = genres_by_name[pair[:genre_name]]
      return nil unless genre

      {
        track_id: pair[:track_id],
        genre_id: genre.id,
        source: TrackGenre.sources[:spotify],
        confidence: 1.0,
        created_at: Time.current,
        updated_at: Time.current,
      }
    end
  end
end
