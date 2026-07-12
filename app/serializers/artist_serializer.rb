# frozen_string_literal: true

class ArtistSerializer
  include Alba::Resource

  attributes :id, :name, :spotify_id, :image_url

  attribute :genres do |artist|
    artist.metadata&.dig("genres") || []
  end

  attribute :followers do |artist|
    artist.metadata&.dig("followers")
  end

  attribute :popularity do |artist|
    artist.metadata&.dig("popularity")
  end
end
