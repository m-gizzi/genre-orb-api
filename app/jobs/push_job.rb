# frozen_string_literal: true

class PushJob < SpotifyJob
  queue_as :push

  def self.fail_push(job, exception, message)
    args = perform_arguments(job).first || {}
    push_session = PushSession.find_by(id: args[:push_session_id])
    return unless push_session

    PushFailureHandler.fail_session(push_session, error_message: "#{message}: #{exception.message}")
  end

  private

  def with_push_session(push_session_id)
    push_session = load_session(push_session_id)
    return unless push_session.active?

    user = push_session.user
    return defer_for_rate_limit(user.id) if rate_limited?(user.id)

    yield(push_session, SpotifyAdapter.new(user.spotify_connection))
  end

  def perform_push(push_session_id)
    with_push_session(push_session_id) do |push_session, adapter|
      response = yield(adapter, push_session.smart_playlist.target_playlist.spotify_id)

      advance(push_session, response&.dig("snapshot_id"))
    end
  end

  def load_session(push_session_id)
    PushSession.includes(smart_playlist: { target_playlist: :user }).find(push_session_id)
  end
end
