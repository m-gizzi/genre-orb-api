# frozen_string_literal: true

class PushFailureHandler
  class << self
    def fail_session(push_session, error_message:)
      return if push_session.failed?

      push_session.update!(
        status: :failed,
        error_message: error_message,
        completed_at: Time.current,
      )
    end
  end
end
