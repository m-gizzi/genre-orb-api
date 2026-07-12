# frozen_string_literal: true

class TrackGenreSerializer
  include Alba::Resource

  attribute :id, &:genre_id
  attribute :name do |track_genre|
    track_genre.genre.name
  end
  attributes :source
end
