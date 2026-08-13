# frozen_string_literal: true

module Genres
  class ArtistGenreWriter
    DEFAULT_CONFIDENCE = 1.0

    def initialize(source:)
      @source = ArtistGenre.sources.fetch(source.to_s)
    end

    # pairs: [{ artist_id:, genre_name:, confidence: }] — confidence optional.
    def call(pairs)
      normalized_pairs = normalize_pairs(pairs)
      return if normalized_pairs.empty?

      genre_names = normalized_pairs.pluck(:genre_name).uniq
      insert_genres(genre_names)
      upsert_artist_genres(genre_names, normalized_pairs)
    end

    private

    attr_reader :source

    def normalize_pairs(pairs)
      pairs.filter_map do |pair|
        name = Genre.normalize_name(pair[:genre_name])
        next unless name

        { artist_id: pair[:artist_id], genre_name: name, confidence: confidence_for(pair) }
      end
    end

    def confidence_for(pair)
      pair.fetch(:confidence, DEFAULT_CONFIDENCE).to_f.clamp(0.0, 1.0)
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

      ArtistGenre.upsert_all(records, unique_by: %i[artist_id genre_id source], update_only: %i[confidence])
    end

    def build_artist_genre_records(normalized_pairs, genres_by_name)
      normalized_pairs
        .filter_map { |pair| build_artist_genre_record(pair, genres_by_name) }
        # Highest confidence wins a duplicate, and rows are ordered by the unique key
        # so concurrent batch jobs cannot deadlock against each other.
        .sort_by { |record| [record[:artist_id], record[:genre_id], -record[:confidence]] }
        .uniq { |record| [record[:artist_id], record[:genre_id]] }
    end

    def build_artist_genre_record(pair, genres_by_name)
      genre = genres_by_name[pair[:genre_name]]
      return nil unless genre

      {
        artist_id: pair[:artist_id],
        genre_id: genre.id,
        source: source,
        confidence: pair[:confidence],
        created_at: Time.current,
        updated_at: Time.current,
      }
    end
  end
end
