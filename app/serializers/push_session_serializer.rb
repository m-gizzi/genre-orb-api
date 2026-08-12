# frozen_string_literal: true

class PushSessionSerializer < SessionSerializer
  attributes :strategy, :tracks_added, :tracks_removed, :match_count, :sampled, :smart_playlist_id

  attribute :smart_playlist_name, &:name
end
