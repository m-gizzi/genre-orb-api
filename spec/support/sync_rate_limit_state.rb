# frozen_string_literal: true

RSpec.configure do |config|
  config.before(:each, type: :request) do
    allow(SyncRateLimitState).to receive(:user_paused?).and_return(false)
    allow(SyncRateLimitState).to receive(:user_resume_at).and_return(nil)
    allow(SyncRateLimitState).to receive(:wait_time_for_user).and_return(0)
  end
end
