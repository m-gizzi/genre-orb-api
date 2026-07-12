# frozen_string_literal: true

class ArtistSummarySerializer
  include Alba::Resource

  attributes :id, :name, :spotify_id, :image_url
end
