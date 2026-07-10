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
end
