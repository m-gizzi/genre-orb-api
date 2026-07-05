# frozen_string_literal: true

class PlaylistSyncCompleter
  def initialize(playlist_session)
    @playlist_session = playlist_session
  end

  def call
    ActiveRecord::Base.transaction do
      version = @playlist_session.playlist_version
      playlist = @playlist_session.playlist

      version.update!(track_count: version.playlist_version_tracks.count)
      playlist.update!(current_version_id: version.id, last_synced_at: Time.current)
      @playlist_session.update!(status: :completed, completed_at: Time.current)

      sync_session = @playlist_session.sync_session
      sync_session.update!(status: :completed, completed_at: Time.current) if sync_session.all_playlists_done?
    end
  end
end
