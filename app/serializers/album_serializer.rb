# frozen_string_literal: true

class AlbumSerializer
  include Alba::Resource

  attributes :id, :title, :spotify_id, :release_year, :artwork_url, :total_tracks

  attribute :saved_tracks do |album|
    params.fetch(:saved_counts).fetch(album.id, 0)
  end

  association :artists, resource: ArtistSummarySerializer
end
