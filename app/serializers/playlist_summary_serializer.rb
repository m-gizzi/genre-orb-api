# frozen_string_literal: true

class PlaylistSummarySerializer
  include Alba::Resource

  attributes :id, :name, :spotify_id, :sync_enabled

  attribute :track_count, &:track_count

  attribute :is_liked_songs, &:liked_songs?
end
