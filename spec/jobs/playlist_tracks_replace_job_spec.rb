# frozen_string_literal: true

require "rails_helper"

RSpec.describe PlaylistTracksReplaceJob do
  let(:user) { create(:user) }
  let(:wanted) { create_list(:track, 2) }
  let(:target) { create(:playlist, :with_spotify, :holding, user: user, tracks: [create(:track)]) }
  let(:smart_playlist) { create(:smart_playlist, :with_rules, target_playlist: target) }

  let(:version) do
    PlaylistVersion.create_for_push!(target).tap do |built|
      SmartPlaylists::PushVersionTrackBuilder.new(built).call(
        wanted.map { |track| SmartPlaylists::PushTrackSet::Entry.new(track_id: track.id, added_at: Time.current) },
      )
    end
  end

  let(:session) do
    create(:push_session, :running, smart_playlist: smart_playlist, playlist_version: version,
                                    strategy: :replace, total_remove_batches: 1,)
  end

  let(:tracks_url) { "#{Spotify::Client::BASE_URL}/playlists/#{target.spotify_id}/tracks" }

  before { create(:service_connection, user: user) }

  def stub_replace
    stub_request(:put, tracks_url)
      .to_return(status: 200, body: { "snapshot_id" => "snap_5" }.to_json,
                 headers: { "Content-Type" => "application/json" },)
  end

  def run(spotify_ids: wanted.map(&:spotify_id))
    described_class.perform_now(push_session_id: session.id, spotify_ids: spotify_ids)
  end

  it "clears and seeds the playlist in one call" do
    stub = stub_request(:put, tracks_url)
           .with(body: { uris: wanted.map { |track| "spotify:track:#{track.spotify_id}" } }.to_json)
           .to_return(status: 200, body: { "snapshot_id" => "snap_5" }.to_json,
                      headers: { "Content-Type" => "application/json" },)

    run

    expect(stub).to have_been_requested
  end

  it "finalizes without an add phase when the seed held everything" do
    stub_replace

    expect { run }.not_to have_enqueued_job(PlaylistTrackAdditionJob)
    expect(session.reload).to be_completed
    expect(target.reload.current_version_id).to eq(version.id)
  end

  context "when the desired set spans more than one batch" do
    before { stub_const("SmartPlaylists::PushBatches::BATCH_SIZE", 1) }

    it "appends the remainder behind the seed" do
      stub_replace

      expect { run(spotify_ids: [wanted.first.spotify_id]) }
        .to have_enqueued_job(PlaylistTrackAdditionJob)
        .with(push_session_id: session.id, spotify_ids: [wanted.second.spotify_id])
    end
  end

  describe "rate-limit deferral" do
    before { allow(SyncRateLimitState).to receive(:wait_time_for_user).with(user.id).and_return(30) }

    it "re-enqueues itself rather than clearing the playlist" do
      stub = stub_replace

      expect { run }.to have_enqueued_job(described_class)
      expect(stub).not_to have_been_requested
    end
  end

  describe "sidekiq_retries_exhausted" do
    it "fails the push session" do
      job = described_class.new(push_session_id: session.id, spotify_ids: %w[a])
      msg = { "args" => [job.serialize], "wrapped" => described_class.name }

      described_class.sidekiq_retries_exhausted_block.call(msg, StandardError.new("boom"))

      expect(session.reload).to be_failed
      expect(session.error_message).to include("Replacing the playlist", "boom")
    end
  end
end
