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
      propagate_genres_to_artists
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
        "genres" => merged_genres(sp_artist),
        "followers" => sp_artist.dig("followers", "total"),
        "popularity" => sp_artist["popularity"],
      }
    end

    def merged_genres(sp_artist)
      existing = existing_genres_by_spotify_id[sp_artist["id"]] || []
      incoming = sp_artist["genres"] || []
      (existing + incoming).uniq { |genre| genre.to_s.downcase }
    end

    def existing_genres_by_spotify_id
      @existing_genres_by_spotify_id ||=
        Artist.where(spotify_id: incoming_spotify_ids).to_h do |artist|
          [artist.spotify_id, artist.metadata&.dig("genres") || []]
        end
    end

    def incoming_spotify_ids
      artists_data.filter_map { |artist_data| artist_data&.dig("id") }
    end

    def propagate_genres_to_artists
      return if incoming_spotify_ids.empty?

      pairs = incoming_artists.flat_map { |artist| genre_pairs_for(artist) }
      Spotify::ArtistGenrePropagator.new.call(pairs)
    end

    def genre_pairs_for(artist)
      genre_names(artist).map { |genre_name| { artist_id: artist.id, genre_name: genre_name } }
    end

    def propagate_genres_to_tracks
      return if incoming_spotify_ids.empty?

      Spotify::TrackGenreDeriver.new.by_artist(incoming_artists.map(&:id))
    end

    def incoming_artists
      @incoming_artists ||= Artist.where(spotify_id: incoming_spotify_ids).to_a
    end

    def genre_names(artist)
      artist.metadata&.dig("genres") || []
    end
  end
end
