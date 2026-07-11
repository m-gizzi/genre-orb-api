# frozen_string_literal: true

class SyncFailureHandler
  class << self
    def fail_playlist_session(playlist_session, error_message:)
      return if playlist_session.failed?

      playlist_session.update!(
        status: :failed,
        error_message: error_message,
        completed_at: Time.current,
      )

      sync_session = playlist_session.sync_session
      sync_session.increment_failed!
      sync_session.reconcile!
    end

    def fail_session(sync_session, error_message:)
      sync_session.sync_session_playlists.where(status: %i[pending fetching_pages]).find_each do |ps|
        ps.update!(status: :failed, error_message: error_message, completed_at: Time.current)
      end

      sync_session.update!(status: :failed, error_message: error_message, completed_at: Time.current)
    end
  end
end
