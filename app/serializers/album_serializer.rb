# frozen_string_literal: true

class AlbumSerializer
  include Alba::Resource

  attributes :id, :title, :spotify_id, :release_year, :artwork_url, :total_tracks

  association :artists, resource: ArtistSummarySerializer
end
