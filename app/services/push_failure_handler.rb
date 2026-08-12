# frozen_string_literal: true

class PushFailureHandler
  class << self
    def fail_session(push_session, error_message:)
      push_session.fail!(error_message: error_message)
    end
  end
end
