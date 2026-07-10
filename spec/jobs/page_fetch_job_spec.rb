# frozen_string_literal: true

require "rails_helper"

RSpec.describe PageFetchJob do
  let(:user) { create(:user) }
  let(:sync_session) { create(:sync_session, user: user) }
  let(:playlist) { create(:playlist, user: user) }
  let(:playlist_session) do
    create(
      :sync_session_playlist,
      sync_session: sync_session,
      playlist: playlist,
      status: :fetching_pages,
    )
  end

  describe "rate-limit deferral" do
    before do
      allow(SyncRateLimitState).to receive(:wait_time_for_user).with(user.id).and_return(30)
    end

    it "re-enqueues itself with the same keyword arguments" do
      expect do
        described_class.perform_now(sync_session_playlist_id: playlist_session.id, page: 2)
      end.to have_enqueued_job(described_class)
        .with(sync_session_playlist_id: playlist_session.id, page: 2)
    end

    it "does not fetch pages while rate limited" do
      allow(Spotify::PlaylistPageFetcher).to receive(:new)

      described_class.perform_now(sync_session_playlist_id: playlist_session.id, page: 2)

      expect(Spotify::PlaylistPageFetcher).not_to have_received(:new)
    end
  end

  describe "sidekiq_retries_exhausted" do
    let(:exception) { StandardError.new("boom") }
    let(:msg) do
      job = described_class.new(sync_session_playlist_id: playlist_session.id, page: 3)
      { "args" => [job.serialize], "wrapped" => described_class.name }
    end

    def run_handler
      described_class.sidekiq_retries_exhausted_block.call(msg, exception)
    end

    it "marks the playlist session as failed" do
      run_handler
      expect(playlist_session.reload.status).to eq("failed")
    end

    it "records the failing page and error message" do
      run_handler
      expect(playlist_session.reload.error_message).to include("Page 3", "boom")
    end

    context "when the playlist session no longer exists" do
      let(:msg) do
        job = described_class.new(sync_session_playlist_id: 999_999, page: 3)
        { "args" => [job.serialize], "wrapped" => described_class.name }
      end

      it "does not raise" do
        expect { run_handler }.not_to raise_error
      end
    end
  end
end
