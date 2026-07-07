# frozen_string_literal: true

RSpec.configure do |config|
  config.before(:each, type: :request) do
    allow(SyncRateLimitState).to receive_messages(user_paused?: false, user_resume_at: nil, wait_time_for_user: 0)
  end
end
