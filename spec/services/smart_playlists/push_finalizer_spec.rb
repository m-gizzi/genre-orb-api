# frozen_string_literal: true

require "rails_helper"

RSpec.describe SmartPlaylists::PushFinalizer do
  let(:user) { create(:user) }
  let(:connection) { create(:service_connection, user: user) }
  let(:adapter) { SpotifyAdapter.new(connection) }
  let(:tracks) { create_list(:track, 2) }
  let(:target) { create(:playlist, :with_spotify, :holding, user: user, tracks: [create(:track)]) }
  let(:smart_playlist) { create(:smart_playlist, :with_rules, target_playlist: target) }

  let(:version) do
    PlaylistVersion.create_for_push!(target).tap do |built|
      SmartPlaylists::PushVersionTrackBuilder.new(built).call(
        tracks.map { |track| SmartPlaylists::PushTrackSet::Entry.new(track_id: track.id, added_at: Time.current) },
      )
    end
  end

  let(:session) do
    create(:push_session, :running, smart_playlist: smart_playlist,
                                    playlist_version: version, spotify_snapshot_id: "snap_from_a_chunk",)
  end

  def stub_snapshot(snapshot_id: "snap_authoritative", status: 200)
    stub_request(:get, "#{Spotify::Client::BASE_URL}/playlists/#{target.spotify_id}")
      .with(query: { fields: "snapshot_id" })
      .to_return(status: status, body: { "snapshot_id" => snapshot_id }.to_json,
                 headers: { "Content-Type" => "application/json" },)
  end

  def finalize
    described_class.new(session, adapter: adapter).call
    session.reload
  end

  before { stub_snapshot }

  it "completes the version and records its track count" do
    finalize

    expect(version.reload).to be_complete
    expect(version.track_count).to eq(2)
  end

  it "swaps the pushed version in as the target's current one" do
    finalize

    expect(target.reload.current_version_id).to eq(version.id)
  end

  it "stamps last_pushed_at without re-validating the rule tree" do
    expect { finalize }.to change { smart_playlist.reload.last_pushed_at }.from(nil)
  end

  it "leaves the sync snapshot bookkeeping alone, so the next sync re-fetches" do
    expect { finalize }.not_to(change { target.reload.last_synced_snapshot_id })
  end

  it "completes the session" do
    expect(finalize).to be_completed
    expect(session.completed_at).to be_present
  end

  it "is idempotent, so a redelivered last batch does not push twice" do
    finalize
    first_pushed_at = smart_playlist.reload.last_pushed_at

    described_class.new(session, adapter: adapter).call

    expect(smart_playlist.reload.last_pushed_at).to eq(first_pushed_at)
  end

  describe "the snapshot the next push will trust" do
    it "re-reads it rather than trusting whichever chunk won the counter lock" do
      finalize

      expect(version.reload.spotify_snapshot_id).to eq("snap_authoritative")
    end

    it "still finishes the push when the re-read fails" do
      stub_snapshot(status: 502)

      expect(finalize).to be_completed
      expect(version.reload.spotify_snapshot_id).to be_nil
      expect(target.reload.current_version_id).to eq(version.id)
    end
  end
end
