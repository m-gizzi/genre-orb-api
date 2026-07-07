# frozen_string_literal: true

class SyncFailureHandler
  class << self
    def fail_playlist_session(playlist_session, error_message:)
      playlist_session.update!(
        status: :failed,
        error_message: error_message,
        completed_at: Time.current,
      )

      check_session_completion(playlist_session.sync_session)
    end

    def fail_session(sync_session, error_message:)
      sync_session.sync_session_playlists.where(status: %i[pending fetching_pages]).find_each do |ps|
        ps.update!(status: :failed, error_message: error_message, completed_at: Time.current)
      end

      sync_session.update!(status: :failed, completed_at: Time.current)
    end

    private

    def check_session_completion(sync_session)
      return if sync_session.sync_session_playlists.exists?(status: %i[pending fetching_pages])

      sync_session.update!(status: :failed, completed_at: Time.current)
    end
  end
end
