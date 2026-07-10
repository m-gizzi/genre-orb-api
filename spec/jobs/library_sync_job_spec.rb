# frozen_string_literal: true

require "rails_helper"

RSpec.describe LibrarySyncJob do
  describe "sidekiq_retries_exhausted" do
    let(:user) { create(:user) }
    let(:exception) { StandardError.new("boom") }
    let(:msg) do
      { "args" => [described_class.new(user.id).serialize], "wrapped" => described_class.name }
    end

    def run_handler
      described_class.sidekiq_retries_exhausted_block.call(msg, exception)
    end

    context "with an active sync session" do
      let!(:session) { create(:sync_session, :running, user: user) }

      it "marks the session as failed" do
        run_handler
        expect(session.reload.status).to eq("failed")
      end

      it "records the error message" do
        run_handler
        expect(session.reload.error_message).to include("boom")
      end

      it "fails in-flight playlist sessions" do
        playlist_session = create(:sync_session_playlist, :fetching, sync_session: session)

        run_handler

        expect(playlist_session.reload.status).to eq("failed")
      end
    end

    context "with no active session" do
      it "does not raise" do
        expect { run_handler }.not_to raise_error
      end
    end
  end
end
