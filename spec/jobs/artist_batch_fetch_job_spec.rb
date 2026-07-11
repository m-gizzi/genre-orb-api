# frozen_string_literal: true

require "rails_helper"

RSpec.describe ArtistBatchFetchJob do
  describe "sidekiq_retries_exhausted" do
    let(:user) { create(:user) }
    let(:session) { create(:artist_metadata_session, user: user) }
    let(:exception) { StandardError.new("splat") }
    let(:msg) do
      job = described_class.new(session_id: session.id, user_id: user.id, artist_ids: [1, 2])
      { "args" => [job.serialize], "wrapped" => described_class.name }
    end

    def run_handler
      described_class.sidekiq_retries_exhausted_block.call(msg, exception)
    end

    it "marks the session as failed" do
      run_handler
      expect(session.reload.status).to eq("failed")
    end

    it "records the error message" do
      run_handler
      expect(session.reload.error_message).to include("splat")
    end

    context "when the session no longer exists" do
      let(:msg) do
        job = described_class.new(session_id: 999_999, user_id: user.id, artist_ids: [1])
        { "args" => [job.serialize], "wrapped" => described_class.name }
      end

      it "does not raise" do
        expect { run_handler }.not_to raise_error
      end
    end
  end
end
