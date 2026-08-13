# frozen_string_literal: true

require "rails_helper"

RSpec.describe SpotifyJob do
  let(:user) { create(:user) }

  before { create(:service_connection, user: user) }

  # A 429 on the app token names no user. Spotify throttles per application, so
  # that pauses everyone rather than escaping as an ordinary retry.
  describe "rate limiting" do
    let(:session) { create(:artist_metadata_session, user: nil, status: :running) }

    before do
      allow(SyncRateLimitState).to receive(:pause!)
      allow(SyncRateLimitState).to receive(:wait_time_for_user).and_return(0, 30)
      allow(Spotify::ArtistBatchProcessor)
        .to receive(:new).and_raise(Spotify::RateLimitError.new(retry_after: 30, user_id: nil))
    end

    it "pauses globally" do
      ArtistBatchFetchJob.perform_now(session_id: session.id, artist_ids: [1])

      expect(SyncRateLimitState).to have_received(:pause!).with(nil, 30)
    end

    it "re-enqueues itself instead of raising" do
      expect { ArtistBatchFetchJob.perform_now(session_id: session.id, artist_ids: [1]) }
        .to have_enqueued_job(ArtistBatchFetchJob).with(session_id: session.id, artist_ids: [1])
    end
  end

  describe ".abandon" do
    it "logs rather than raising for a job with no failure handling of its own" do
      allow(Rails.logger).to receive(:error)

      described_class.abandon({ some: "args" }, StandardError.new("splat"))

      expect(Rails.logger).to have_received(:error).with(/splat/)
    end
  end

  describe "#guard_connection!" do
    let(:job) { PageFetchJob.new }

    it "returns the connection when it is healthy" do
      expect(job.send(:guard_connection!, user)).to eq(user.spotify_connection)
    end

    it "raises rather than calling Spotify when the connection needs reauthorizing" do
      user.spotify_connection.update!(needs_reauth: true)

      expect { job.send(:guard_connection!, user.reload) }.to raise_error(Spotify::ReauthRequiredError)
    end

    it "raises when there is no connection at all" do
      expect { job.send(:guard_connection!, create(:user)) }.to raise_error(Spotify::ReauthRequiredError)
    end
  end

  describe "discarding on a required reconnect" do
    let(:session) { create(:artist_metadata_session, user: user, status: :running) }

    it "fails the owning session instead of retrying" do
      allow(Spotify::ArtistBatchProcessor).to receive(:new).and_raise(Spotify::ReauthRequiredError, "reconnect")

      expect { ArtistBatchFetchJob.perform_now(session_id: session.id, artist_ids: [1]) }.not_to raise_error
      expect(session.reload).to be_failed
    end
  end
end
