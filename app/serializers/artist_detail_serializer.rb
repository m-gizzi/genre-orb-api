# frozen_string_literal: true

class ArtistDetailSerializer < ArtistSerializer
  association :albums, resource: AlbumSummarySerializer
end
