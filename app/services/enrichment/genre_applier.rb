# frozen_string_literal: true

module Enrichment
  # The two steps every provider ends with: write the artist's genres for this source,
  # then project them onto the artist's tracks.
  class GenreApplier
    def initialize(source:)
      @writer = Genres::ArtistGenreWriter.new(source: source)
      @deriver = Genres::TrackGenreDeriver.new
    end

    def call(artist_id, genres)
      return if genres.blank?

      writer.call(genres.map { |genre| pair_for(artist_id, genre) })
      deriver.by_artist([artist_id])
    end

    private

    attr_reader :writer, :deriver

    def pair_for(artist_id, genre)
      { artist_id: artist_id, genre_name: genre[:name], confidence: genre[:confidence] }
    end
  end
end
