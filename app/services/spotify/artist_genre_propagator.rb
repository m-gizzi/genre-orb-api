# frozen_string_literal: true

module Spotify
  class ArtistGenrePropagator
    def call(pairs)
      normalized_pairs = normalize_pairs(pairs)
      return if normalized_pairs.empty?

      genre_names = normalized_pairs.pluck(:genre_name).uniq
      insert_genres(genre_names)
      upsert_artist_genres(genre_names, normalized_pairs)
    end

    private

    def normalize_pairs(pairs)
      pairs.filter_map do |pair|
        name = Genre.normalize_name(pair[:genre_name])
        { artist_id: pair[:artist_id], genre_name: name } if name
      end
    end

    def insert_genres(genre_names)
      genre_records = genre_names.map do |name|
        { name: name, created_at: Time.current, updated_at: Time.current }
      end

      Genre.insert_all(genre_records, unique_by: :name) if genre_records.any?
    end

    def upsert_artist_genres(genre_names, normalized_pairs)
      genres_by_name = Genre.where(name: genre_names).index_by(&:name)
      records = build_artist_genre_records(normalized_pairs, genres_by_name)
      return if records.empty?

      ArtistGenre.insert_all(records, unique_by: %i[artist_id genre_id])
    end

    def build_artist_genre_records(normalized_pairs, genres_by_name)
      normalized_pairs
        .filter_map { |pair| build_artist_genre_record(pair, genres_by_name) }
        .uniq { |record| [record[:artist_id], record[:genre_id]] }
        .sort_by { |record| [record[:artist_id], record[:genre_id]] }
    end

    def build_artist_genre_record(pair, genres_by_name)
      genre = genres_by_name[pair[:genre_name]]
      return nil unless genre

      {
        artist_id: pair[:artist_id],
        genre_id: genre.id,
        created_at: Time.current,
        updated_at: Time.current,
      }
    end
  end
end
