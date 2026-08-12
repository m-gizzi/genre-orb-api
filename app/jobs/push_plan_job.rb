# frozen_string_literal: true

class PushPlanJob < PushJob
  sidekiq_retries_exhausted do |job, exception|
    fail_push(job, exception, "Push planning failed after retries")
  end

  def perform(push_session_id:)
    with_push_session(push_session_id) do |push_session, adapter|
      plan(push_session, adapter)
    end
  end

  private

  # A rule set too slow for the planner's statement timeout is slow on every retry,
  # so it fails here rather than through five more 30s scans.
  def plan(push_session, adapter)
    SmartPlaylists::PushPlanner.new(push_session, adapter: adapter).call
  rescue ActiveRecord::QueryCanceled
    PushFailureHandler.fail_session(
      push_session,
      error_message: I18n.t("api.smart_playlists.evaluation_timeout"),
    )
  end
end
