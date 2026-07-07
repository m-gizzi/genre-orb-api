# frozen_string_literal: true

module Spotify
  class ArtistMetadataUpserter
    def initialize(spotify_response)
      @artists_data = spotify_response["artists"] || []
    end

    def call
      return if @artists_data.empty?

      update_artists
      propagate_genres_to_tracks
    end

    private

    def update_artists
      updates = @artists_data.filter_map do |sp_artist|
        next unless sp_artist && sp_artist["id"]

        {
          spotify_id: sp_artist["id"],
          name: sp_artist["name"],
          image_url: sp_artist.dig("images", 0, "url"),
          metadata: build_metadata(sp_artist),
          metadata_fetched_at: Time.current,
          updated_at: Time.current
        }
      end.sort_by { |a| a[:spotify_id] }

      return if updates.empty?

      Artist.upsert_all(
        updates,
        unique_by: :spotify_id,
        update_only: %i[name image_url metadata metadata_fetched_at]
      )
    end

    def build_metadata(sp_artist)
      {
        "genres" => sp_artist["genres"] || [],
        "followers" => sp_artist.dig("followers", "total"),
        "popularity" => sp_artist["popularity"]
      }
    end

    def propagate_genres_to_tracks
      spotify_ids = @artists_data.filter_map { |a| a&.dig("id") }
      return if spotify_ids.empty?

      artists = Artist.where(spotify_id: spotify_ids).includes(:tracks)

      genre_names = Set.new
      track_genre_pairs = []

      artists.each do |artist|
        genres = artist.metadata&.dig("genres") || []
        next if genres.empty?

        genres.each { |g| genre_names.add(Genre.normalize_name(g)) }

        artist.tracks.each do |track|
          genres.each do |genre_name|
            normalized = Genre.normalize_name(genre_name)
            next unless normalized

            track_genre_pairs << { track_id: track.id, genre_name: normalized }
          end
        end
      end

      return if genre_names.empty?

      upsert_genres(genre_names)
      upsert_track_genres(track_genre_pairs, genre_names)
    end

    def upsert_genres(genre_names)
      genre_records = genre_names.compact.map do |name|
        { name: name, created_at: Time.current, updated_at: Time.current }
      end

      Genre.upsert_all(genre_records, unique_by: :name) if genre_records.any?
    end

    def upsert_track_genres(track_genre_pairs, genre_names)
      return if track_genre_pairs.empty?

      genres_by_name = Genre.where(name: genre_names.to_a).index_by(&:name)

      track_genre_records = track_genre_pairs.filter_map do |pair|
        genre = genres_by_name[pair[:genre_name]]
        next unless genre

        {
          track_id: pair[:track_id],
          genre_id: genre.id,
          source: TrackGenre.sources[:spotify],
          confidence: 1.0,
          created_at: Time.current,
          updated_at: Time.current
        }
      end.uniq { |r| [r[:track_id], r[:genre_id]] }

      return if track_genre_records.empty?

      TrackGenre.upsert_all(track_genre_records, unique_by: %i[track_id genre_id])
    end
  end
end
