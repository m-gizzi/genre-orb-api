# frozen_string_literal: true

class PushPlanJob < PushJob
  sidekiq_retries_exhausted do |job, exception|
    fail_push(job, exception, "Push planning failed after retries")
  end

  def perform(push_session_id:)
    push_session = load_session(push_session_id)
    user = push_session.user

    if rate_limited?(user.id)
      defer_for_rate_limit(user.id)
      return
    end

    SmartPlaylists::PushPlanner.new(push_session, adapter: adapter_for(user)).call
  end

  private

  def adapter_for(user)                                                                                                                                                  
    SpotifyAdapter.new(user.spotify_connection)                                                                                                                          
  end
end
