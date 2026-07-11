# frozen_string_literal: true

module Spotify
  class TrackGenrePropagator
    def call(pairs)
      normalized_pairs = normalize_pairs(pairs)
      return if normalized_pairs.empty?

      genre_names = normalized_pairs.pluck(:genre_name).uniq
      insert_genres(genre_names)
      upsert_track_genres(genre_names, normalized_pairs)
    end

    private

    def normalize_pairs(pairs)
      pairs.filter_map do |pair|
        name = Genre.normalize_name(pair[:genre_name])
        { track_id: pair[:track_id], genre_name: name } if name
      end
    end

    def insert_genres(genre_names)
      genre_records = genre_names.map do |name|
        { name: name, created_at: Time.current, updated_at: Time.current }
      end

      Genre.insert_all(genre_records, unique_by: :name) if genre_records.any?
    end

    def upsert_track_genres(genre_names, normalized_pairs)
      genres_by_name = Genre.where(name: genre_names).index_by(&:name)
      track_genre_records = build_track_genre_records(normalized_pairs, genres_by_name)
      return if track_genre_records.empty?

      TrackGenre.upsert_all(track_genre_records, unique_by: %i[track_id genre_id source])
    end

    def build_track_genre_records(normalized_pairs, genres_by_name)
      normalized_pairs
        .filter_map { |pair| build_track_genre_record(pair, genres_by_name) }
        .uniq { |record| [record[:track_id], record[:genre_id], record[:source]] }
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
