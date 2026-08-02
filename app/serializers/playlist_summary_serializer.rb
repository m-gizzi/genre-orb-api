# frozen_string_literal: true

class PlaylistSummarySerializer
  include Alba::Resource

  attributes :id, :name, :spotify_id

  attribute :is_liked_songs, &:liked_songs?
end
