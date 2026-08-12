# frozen_string_literal: true

module SyncStatusRendering
  extend ActiveSupport::Concern

  class_methods do
    def sync_outcomes(responses)
      @sync_outcome_responses = responses.freeze
    end

    def sync_outcome_responses
      @sync_outcome_responses ||
        raise(NotImplementedError, "#{name} must declare sync outcomes with `sync_outcomes`")
    end
  end

  private

  def rate_limit_info
    rate_limited = SyncRateLimitState.user_paused?(current_user.id)
    {
      rate_limited: rate_limited,
      rate_limit_resume_at: rate_limited ? SyncRateLimitState.user_resume_at(current_user.id)&.iso8601 : nil,
    }
  end

  def render_sync_outcome(outcome)
    response = self.class.sync_outcome_responses.fetch(outcome)
    render_error(I18n.t(response[:key]), status: response[:status])
  end
end
