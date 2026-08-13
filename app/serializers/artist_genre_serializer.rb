# frozen_string_literal: true

class ArtistGenreSerializer
  include Alba::Resource

  attributes :id, :genre_id, :source, :confidence

  attribute :name do |artist_genre|
    artist_genre.genre.name
  end
end
