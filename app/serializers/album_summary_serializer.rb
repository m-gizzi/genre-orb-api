# frozen_string_literal: true

class AlbumSummarySerializer
  include Alba::Resource

  attributes :id, :title, :spotify_id, :release_year, :artwork_url
end
