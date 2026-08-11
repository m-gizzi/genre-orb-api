# frozen_string_literal: true

require "rails_helper"

RSpec.describe PlaylistTrackAdditionJob do
  let(:user) { create(:user) }
  let(:target) { create(:playlist, :with_spotify, user: user) }
  let(:smart_playlist) { create(:smart_playlist, :with_rules, target_playlist: target) }
  let(:version) { PlaylistVersion.create_for_push!(target) }
  let(:session) do
    create(:push_session, :running, smart_playlist: smart_playlist, playlist_version: version,
                                    total_add_batches: 2,)
  end

  let(:add_url) { "#{Spotify::Client::BASE_URL}/playlists/#{target.spotify_id}/tracks" }

  before { create(:service_connection, user: user) }

  def stub_add(snapshot_id: "snap_1")
    stub_request(:post, add_url)
      .to_return(status: 201, body: { "snapshot_id" => snapshot_id }.to_json,
                 headers: { "Content-Type" => "application/json" },)
  end

  def run(spotify_ids: %w[a b])
    described_class.perform_now(push_session_id: session.id, spotify_ids: spotify_ids)
  end

  it "posts the batch's uris to the target playlist" do
    stub = stub_request(:post, add_url)
           .with(body: { uris: ["spotify:track:a", "spotify:track:b"] }.to_json)
           .to_return(status: 201, body: { "snapshot_id" => "snap_1" }.to_json,
                      headers: { "Content-Type" => "application/json" },)

    run

    expect(stub).to have_been_requested
  end

  it "advances the phase counter and records the snapshot" do
    stub_add(snapshot_id: "snap_7")

    run

    expect(session.reload.completed_add_batches).to eq(1)
    expect(session.spotify_snapshot_id).to eq("snap_7")
  end

  it "does not finalize until the last batch of the phase lands" do
    stub_add

    run

    expect(session.reload).to be_running
    expect(target.reload.current_version_id).to be_nil
  end

  it "finalizes on the last batch, whichever order the batches arrive in" do
    stub_add

    run(spotify_ids: %w[a])
    run(spotify_ids: %w[b])

    expect(session.reload).to be_completed
    expect(target.reload.current_version_id).to eq(version.id)
  end

  describe "rate-limit deferral" do
    before { allow(SyncRateLimitState).to receive(:wait_time_for_user).with(user.id).and_return(30) }

    it "re-enqueues itself with the same batch" do
      expect { run }.to have_enqueued_job(described_class)
        .with(push_session_id: session.id, spotify_ids: %w[a b])
    end

    it "does not advance the counter while deferred" do
      run

      expect(session.reload.completed_add_batches).to eq(0)
    end
  end

  describe "sidekiq_retries_exhausted" do
    let(:msg) do
      job = described_class.new(push_session_id: session.id, spotify_ids: %w[a])
      { "args" => [job.serialize], "wrapped" => described_class.name }
    end

    it "fails the push session with the batch's error" do
      described_class.sidekiq_retries_exhausted_block.call(msg, StandardError.new("boom"))

      expect(session.reload).to be_failed
      expect(session.error_message).to include("Adding tracks", "boom")
    end

    it "does not raise when the session is gone" do
      job = described_class.new(push_session_id: 999_999, spotify_ids: %w[a])
      gone = { "args" => [job.serialize], "wrapped" => described_class.name }

      expect { described_class.sidekiq_retries_exhausted_block.call(gone, StandardError.new("boom")) }
        .not_to raise_error
    end
  end
end
