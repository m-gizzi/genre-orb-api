# frozen_string_literal: true

require "rails_helper"

RSpec.describe PlaylistSyncFinalizer do
  let(:user) { create(:user) }
  let(:sync_session) { create(:sync_session, :running, user: user, total_playlists: 1) }
  let(:playlist) do
    create(:playlist, :with_spotify, :holding, user: user, tracks: [create(:track)],
                                               last_synced_snapshot_id: "snap_before",)
  end
  let(:baseline) { playlist.current_version }
  let(:synced_version) { create(:playlist_version, :with_tracks, playlist: playlist, tracks_count: 2) }

  let!(:playlist_session) do
    create(:sync_session_playlist, :fetching, sync_session: sync_session, playlist: playlist,
                                              playlist_version: synced_version, baseline_version: baseline,)
  end

  def finalize
    described_class.new(playlist_session).complete!
    playlist.reload
  end

  describe "#complete!" do
    it "swaps the synced version in when nothing moved the baseline" do
      expect(finalize.current_version_id).to eq(synced_version.id)
    end

    it "records the snapshot the sync read" do
      playlist.update!(last_seen_snapshot_id: "snap_after")

      finalize

      expect(playlist.last_synced_snapshot_id).to eq("snap_after")
      expect(playlist.last_synced_at).to be_present
    end

    it "completes the version and its track count" do
      finalize

      expect(synced_version.reload).to be_complete
      expect(synced_version.track_count).to eq(2)
    end

    it "leaves the version's snapshot as stamped at setup" do
      synced_version.update!(spotify_snapshot_id: "snap_at_setup")
      playlist.update!(last_seen_snapshot_id: "snap_moved_since")

      finalize

      expect(synced_version.reload.spotify_snapshot_id).to eq("snap_at_setup")
    end

    it "completes the playlist session either way" do
      create(:playlist_version, :current, playlist: playlist)

      finalize

      expect(playlist_session.reload).to be_completed
    end
  end

  describe "when a push installs its version while the pages are still coming down" do
    it "keeps the push's version rather than reverting to this read" do
      pushed_version = create(:playlist_version, :current, playlist: playlist)

      expect(finalize.current_version_id).to eq(pushed_version.id)
    end

    it "leaves last_synced_* stale so the next run re-reads what the push wrote" do
      create(:playlist_version, :current, playlist: playlist)
      playlist.update!(last_seen_snapshot_id: "snap_after")

      finalize

      expect(playlist.last_synced_snapshot_id).to eq("snap_before")
      expect(playlist.last_synced_at).to be_nil
    end
  end

  describe "#mark_as_skipped!" do
    it "records why the playlist was skipped" do
      described_class.new(playlist_session).mark_as_skipped!(:push_in_flight)

      expect(playlist_session.reload).to be_skipped
      expect(playlist_session.skip_reason).to eq("push_in_flight")
    end
  end
end
