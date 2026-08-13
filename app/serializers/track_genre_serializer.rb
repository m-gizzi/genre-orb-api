# frozen_string_literal: true

class TrackGenreSerializer
  include Alba::Resource

  attributes :id, :genre_id, :source, :confidence

  attribute :name do |track_genre|
    track_genre.genre.name
  end
end
