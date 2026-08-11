# frozen_string_literal: true

require "rails_helper"

RSpec.describe PlaylistTrackRemovalJob do
  let(:user) { create(:user) }
  let(:stale) { create(:track) }
  let(:wanted) { create(:track) }
  let(:target) { create(:playlist, :with_spotify, :holding, user: user, tracks: [stale]) }
  let(:smart_playlist) { create(:smart_playlist, :with_rules, target_playlist: target) }

  let(:version) do
    PlaylistVersion.create_for_push!(target).tap do |built|
      SmartPlaylists::PushVersionTrackBuilder.new(built).call(
        [SmartPlaylists::PushTrackSet::Entry.new(track_id: wanted.id, added_at: Time.current)],
      )
    end
  end

  let(:session) do
    create(:push_session, :running, smart_playlist: smart_playlist, playlist_version: version,
                                    total_remove_batches: 1,)
  end

  let(:remove_url) { "#{Spotify::Client::BASE_URL}/playlists/#{target.spotify_id}/tracks" }

  before { create(:service_connection, user: user) }

  def stub_remove
    stub_request(:delete, remove_url)
      .to_return(status: 200, body: { "snapshot_id" => "snap_2" }.to_json,
                 headers: { "Content-Type" => "application/json" },)
  end

  def run(spotify_ids: [stale.spotify_id])
    described_class.perform_now(push_session_id: session.id, spotify_ids: spotify_ids)
  end

  it "sends the batch's uris in a DELETE body" do
    stub = stub_request(:delete, remove_url)
           .with(body: { tracks: [{ uri: "spotify:track:#{stale.spotify_id}" }] }.to_json)
           .to_return(status: 200, body: { "snapshot_id" => "snap_2" }.to_json,
                      headers: { "Content-Type" => "application/json" },)

    run

    expect(stub).to have_been_requested
  end

  it "starts the add phase once the last removal lands" do
    stub_remove

    expect { run }.to have_enqueued_job(PlaylistTrackAdditionJob)
      .with(push_session_id: session.id, spotify_ids: [wanted.spotify_id])
  end

  it "sizes the add phase from the plan it re-derives" do
    stub_remove

    run

    expect(session.reload.completed_remove_batches).to eq(1)
  end

  it "waits for every removal batch before adding anything" do
    session.update!(total_remove_batches: 2)
    stub_remove

    expect { run }.not_to have_enqueued_job(PlaylistTrackAdditionJob)
  end

  context "when the push has nothing to add" do
    let(:version) { PlaylistVersion.create_for_push!(target) }

    it "finalizes straight from the remove phase" do
      stub_remove

      run

      expect(session.reload).to be_completed
      expect(target.reload.current_version_id).to eq(version.id)
    end
  end

  describe "rate-limit deferral" do
    before { allow(SyncRateLimitState).to receive(:wait_time_for_user).with(user.id).and_return(30) }

    it "re-enqueues itself with the same batch" do
      expect { run }.to have_enqueued_job(described_class)
        .with(push_session_id: session.id, spotify_ids: [stale.spotify_id])
    end
  end

  describe "sidekiq_retries_exhausted" do
    it "fails the push session" do
      job = described_class.new(push_session_id: session.id, spotify_ids: %w[a])
      msg = { "args" => [job.serialize], "wrapped" => described_class.name }

      described_class.sidekiq_retries_exhausted_block.call(msg, StandardError.new("boom"))

      expect(session.reload).to be_failed
      expect(session.error_message).to include("Removing tracks", "boom")
    end
  end
end
