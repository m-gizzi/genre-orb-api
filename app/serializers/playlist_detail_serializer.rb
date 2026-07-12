# frozen_string_literal: true

class PlaylistDetailSerializer < PlaylistSerializer
  attribute :current_version do |playlist|
    version = playlist.current_version
    next nil unless version

    {
      id: version.id,
      version_number: version.version_number,
      track_count: version.track_count,
      status: version.status,
    }
  end
end
