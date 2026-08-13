# frozen_string_literal: true

require "rails_helper"

RSpec.describe ScheduledPlaylistDiscoveryJob do
  let(:user) { create(:user) }
  let(:run) { create(:scheduled_run, stage_total: 1, stage_completed: 0) }

  before do
    create(:service_connection, user: user)
    allow(SyncRateLimitState).to receive(:wait_time_for_user).and_return(0)
  end

  it "fetches the user's playlists and credits the stage counter" do
    fetcher = instance_spy(Spotify::PlaylistMetadataFetcher)
    allow(Spotify::PlaylistMetadataFetcher).to receive(:new).with(user).and_return(fetcher)

    described_class.perform_now(scheduled_run_id: run.id, user_id: user.id)

    expect(fetcher).to have_received(:call)
    expect(run.reload.stage_completed).to eq(1)
  end

  it "defers itself while the user is rate limited" do
    allow(SyncRateLimitState).to receive(:wait_time_for_user).and_return(30)
    allow(Spotify::PlaylistMetadataFetcher).to receive(:new)

    expect { described_class.perform_now(scheduled_run_id: run.id, user_id: user.id) }
      .to have_enqueued_job(described_class).with(scheduled_run_id: run.id, user_id: user.id)
    expect(Spotify::PlaylistMetadataFetcher).not_to have_received(:new)
  end

  it "credits the counter for a user who needs to reconnect, so the stage still closes" do
    user.spotify_connection.update!(needs_reauth: true)

    expect { described_class.perform_now(scheduled_run_id: run.id, user_id: user.id) }.not_to raise_error
    expect(run.reload.stage_completed).to eq(1)
  end

  describe "sidekiq_retries_exhausted" do
    let(:msg) do
      job = described_class.new(scheduled_run_id: run.id, user_id: user.id)
      { "args" => [job.serialize], "wrapped" => described_class.name }
    end

    it "credits the counter so one broken user cannot hold the stage open" do
      described_class.sidekiq_retries_exhausted_block.call(msg, StandardError.new("splat"))

      expect(run.reload.stage_completed).to eq(1)
    end

    it "does not raise when the run is gone" do
      run.destroy!

      expect { described_class.sidekiq_retries_exhausted_block.call(msg, StandardError.new("splat")) }
        .not_to raise_error
    end
  end
end
