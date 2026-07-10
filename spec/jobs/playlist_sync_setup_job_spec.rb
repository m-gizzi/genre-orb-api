# frozen_string_literal: true

require "rails_helper"

RSpec.describe PlaylistSyncSetupJob do
  describe "sidekiq_retries_exhausted" do
    let(:playlist_session) { create(:sync_session_playlist, status: :pending) }
    let(:exception) { StandardError.new("kaboom") }
    let(:msg) do
      { "args" => [described_class.new(playlist_session.id).serialize], "wrapped" => described_class.name }
    end

    def run_handler
      described_class.sidekiq_retries_exhausted_block.call(msg, exception)
    end

    it "marks the playlist session as failed" do
      run_handler
      expect(playlist_session.reload.status).to eq("failed")
    end

    it "records the error message" do
      run_handler
      expect(playlist_session.reload.error_message).to include("kaboom")
    end

    context "when the playlist session no longer exists" do
      let(:msg) do
        { "args" => [described_class.new(999_999).serialize], "wrapped" => described_class.name }
      end

      it "does not raise" do
        expect { run_handler }.not_to raise_error
      end
    end
  end
end
