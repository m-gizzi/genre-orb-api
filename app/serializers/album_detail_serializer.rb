# frozen_string_literal: true

class AlbumDetailSerializer < AlbumSerializer
  association :tracks, resource: TrackSerializer
end
