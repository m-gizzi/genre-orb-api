# frozen_string_literal: true

require "rails_helper"

RSpec.describe SmartPlaylists::PushFinalizer do
  let(:user) { create(:user) }
  let(:tracks) { create_list(:track, 2) }
  let(:target) do
    create(:playlist, :with_spotify, :holding, user: user,
                                               tracks: [create(:track)], version_snapshot_id: "snap_baseline",)
  end
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
                                    playlist_version: version, spotify_snapshot_id: "snap_from_last_write",)
  end

  def finalize
    described_class.new(session).call
    session.reload
  end

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

    described_class.new(session).call

    expect(smart_playlist.reload.last_pushed_at).to eq(first_pushed_at)
  end

  describe "sessions it must not complete" do
    it "leaves a failed session failed when a sibling batch finishes afterwards" do
      PushFailureHandler.fail_session(session, error_message: "Removing tracks failed after retries")

      finalize

      expect(session).to be_failed
      expect(session.error_message).to include("Removing tracks failed after retries")
    end

    it "does not swap in a version for a failed session" do
      PushFailureHandler.fail_session(session, error_message: "boom")

      expect { finalize }.not_to(change { target.reload.current_version_id })
    end

    it "leaves a skipped session skipped" do
      session.update!(status: :skipped, completed_at: Time.current)

      finalize

      expect(session).to be_skipped
      expect(target.reload.current_version_id).not_to eq(version.id)
    end

    it "stands down when the planner has discarded the version it would complete" do
      session.update!(playlist_version: nil)

      finalize

      expect(session).to be_running
      expect(smart_playlist.reload.last_pushed_at).to be_nil
    end
  end

  describe "the snapshot the next push will trust" do
    it "takes it from the last write response, never from a fresh read" do
      finalize

      expect(version.reload.spotify_snapshot_id).to eq("snap_from_last_write")
      expect(a_request(:any, /#{Regexp.escape(Spotify::Client::BASE_URL)}/o)).not_to have_been_made
    end

    it "keeps the validated baseline when the push wrote nothing" do
      session.update!(spotify_snapshot_id: nil)

      finalize

      expect(version.reload.spotify_snapshot_id).to eq("snap_baseline")
    end
  end
end
