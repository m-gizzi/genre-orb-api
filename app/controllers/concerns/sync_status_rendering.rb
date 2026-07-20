# frozen_string_literal: true

module SyncStatusRendering
  extend ActiveSupport::Concern

  private

  def rate_limit_info
    rate_limited = SyncRateLimitState.user_paused?(current_user.id)
    {
      rate_limited: rate_limited,
      rate_limit_resume_at: rate_limited ? SyncRateLimitState.user_resume_at(current_user.id)&.iso8601 : nil,
    }
  end

  def render_sync_outcome(outcome)
    response = self.class::SYNC_OUTCOME_RESPONSES.fetch(outcome)
    render_error(I18n.t(response[:key]), status: response[:status])
  end

  def serialize_session(session)
    {
      id: session.id,
      status: session.status,
      progress: session.progress,
      error_message: session.error_message,
      started_at: session.started_at&.iso8601,
      completed_at: session.completed_at&.iso8601,
    }
  end
end
