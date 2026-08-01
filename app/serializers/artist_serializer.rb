# frozen_string_literal: true

class ArtistSerializer
  include Alba::Resource

  attributes :id, :name, :spotify_id, :image_url

  attribute :genres do |artist|
    GenreSerializer.new(artist.genres).serializable_hash
  end

  attribute :followers do |artist|
    artist.metadata&.dig("followers")
  end

  attribute :popularity do |artist|
    artist.metadata&.dig("popularity")
  end
end
