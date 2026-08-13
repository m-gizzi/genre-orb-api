# frozen_string_literal: true

module ScheduledRuns
  class EligibleUsers
    def self.call
      User.joins(:spotify_connection)
          .where(service_connections: { needs_reauth: false })
          .where(id: Playlist.sync_enabled.available.select(:user_id))
          .distinct
    end
  end
end
