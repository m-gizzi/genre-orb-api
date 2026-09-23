# frozen_string_literal: true

require "rails_helper"

RSpec.describe PlaylistVersions::Pruner do
  let(:playlist) { create(:playlist) }

  # track_count mirrors the rows, the way a finalized version's does in production — the
  # pruner sizes its batches off the column rather than counting rows itself.
  def version(number, on: playlist, tracks: 0)
    create(
      :playlist_version,
      playlist: on,
      version_number: number,
      created_at: 1.day.ago,
      track_count: tracks,
    ).tap do |built|
      tracks.times { |i| create(:playlist_version_track, playlist_version: built, position: i) }
    end
  end

  def with_stale_version(tracks: 0)
    stale = version(1, tracks: tracks)
    (2..4).each { |n| version(n) }
    stale
  end

  def prune(...)
    described_class.new(...).call
  end

  it "deletes a version past the retention window" do
    stale = with_stale_version

    prune

    expect(PlaylistVersion.exists?(stale.id)).to be(false)
  end

  it "deletes the pruned version's tracks with it" do
    stale = with_stale_version(tracks: 3)

    prune

    expect(PlaylistVersionTrack.where(playlist_version_id: stale.id)).to be_empty
  end

  it "counts what it removed" do
    with_stale_version(tracks: 3)

    expect(prune).to have_attributes(versions: 1, tracks: 3, skipped: false)
  end

  it "keeps the retained versions" do
    with_stale_version
    keepers = playlist.versions.where(version_number: 2..4).pluck(:id)

    prune

    expect(PlaylistVersion.where(id: keepers).count).to eq(3)
  end

  it "leaves a playlist inside the window untouched" do
    (1..3).each { |n| version(n) }

    expect { prune }.not_to change(PlaylistVersion, :count)
  end

  it "never deletes the current version" do
    oldest = version(1)
    (2..6).each { |n| version(n) }
    playlist.update!(current_version: oldest)

    prune

    expect(PlaylistVersion.exists?(oldest.id)).to be(true)
  end

  it "is idempotent" do
    with_stale_version
    prune

    expect(prune.versions).to eq(0)
  end

  it "prunes each playlist independently" do
    other = create(:playlist)
    with_stale_version
    other_versions = (1..3).map { |n| version(n, on: other) }

    prune

    expect(PlaylistVersion.where(id: other_versions.map(&:id)).count).to eq(3)
  end

  describe "versions a live session is holding" do
    let(:smart_playlist) { create(:smart_playlist, :with_rules) }

    def expect_spared(stale)
      expect { prune }.not_to change(PlaylistVersion, :count)
      expect(PlaylistVersion.exists?(stale.id)).to be(true)
    end

    it "spares a version a pending push is building" do
      stale = with_stale_version
      create(:push_session, smart_playlist: smart_playlist, playlist_version: stale)

      expect_spared(stale)
    end

    it "spares a baseline a running push pinned" do
      stale = with_stale_version
      create(:push_session, :running, smart_playlist: smart_playlist, baseline_version: stale)

      expect_spared(stale)
    end

    it "spares a version a pending sync is filling" do
      stale = with_stale_version
      create(:sync_session_playlist, playlist: playlist, playlist_version: stale)

      expect_spared(stale)
    end

    it "spares a baseline a fetching sync pinned" do
      stale = with_stale_version
      create(:sync_session_playlist, :fetching, playlist: playlist, baseline_version: stale)

      expect_spared(stale)
    end

    it "counts the versions it stood off" do
      stale = with_stale_version
      create(:push_session, :running, smart_playlist: smart_playlist, baseline_version: stale)

      expect(prune.pinned).to eq(1)
    end
  end

  describe "versions a finished session still points at" do
    let(:smart_playlist) { create(:smart_playlist, :with_rules) }

    it "releases a completed push session and deletes the version" do
      stale = with_stale_version
      session = create(:push_session, :completed, smart_playlist: smart_playlist, playlist_version: stale)

      prune

      expect(session.reload.playlist_version_id).to be_nil
      expect(PlaylistVersion.exists?(stale.id)).to be(false)
    end

    it "releases a failed push session's baseline" do
      stale = with_stale_version
      session = create(:push_session, :failed, smart_playlist: smart_playlist, baseline_version: stale)

      prune

      expect(session.reload.baseline_version_id).to be_nil
    end

    it "releases a completed sync session playlist" do
      stale = with_stale_version
      session = create(:sync_session_playlist, :completed, playlist: playlist, playlist_version: stale)

      prune

      expect(session.reload.playlist_version_id).to be_nil
      expect(PlaylistVersion.exists?(stale.id)).to be(false)
    end

    it "releases a skipped sync session playlist's baseline" do
      stale = with_stale_version
      session = create(:sync_session_playlist, :skipped, playlist: playlist, baseline_version: stale)

      prune

      expect(session.reload.baseline_version_id).to be_nil
    end

    it "leaves the session row itself intact" do
      stale = with_stale_version
      session = create(:push_session, :failed, smart_playlist: smart_playlist, playlist_version: stale)

      prune

      expect(session.reload).to be_failed
      expect(session.error_message).to be_present
    end
  end

  describe "budget" do
    it "stops at the deadline and reports itself exhausted" do
      with_stale_version
      create(:playlist)

      result = prune(deadline: 1.second.ago)

      expect(result.exhausted).to be(true)
    end

    it "leaves the untouched playlists for the next run" do
      with_stale_version

      prune(deadline: 1.second.ago)

      expect(prune.versions).to eq(1)
    end

    it "does not call itself exhausted when it ran out of playlists rather than time" do
      with_stale_version

      expect(prune.exhausted).to be(false)
    end

    it "counts the playlists it scanned, not the ones it pruned" do
      with_stale_version
      create(:playlist)

      expect(prune.scanned).to eq(2)
    end
  end

  describe "resuming where the last run stopped" do
    let(:store) { {} }
    let(:redis) { instance_double(RedisClient) }

    before do
      allow(redis).to receive(:call) do |command, key, value, *|
        case command
        when "GET" then store[key]
        when "SET" then store[key] = value.to_s
        when "DEL" then store.delete(key)
        end
      end
      stub_app_redis(redis)
    end

    it "keeps its place rather than resetting it when it stops short" do
      with_stale_version
      create(:playlist)
      PlaylistVersions::SweepCursor.write(playlist.id)

      prune(deadline: 1.second.ago)

      expect(PlaylistVersions::SweepCursor.read).to eq(playlist.id)
    end

    it "skips playlists at or below a cursor a previous run left behind" do
      stale = with_stale_version
      PlaylistVersions::SweepCursor.write(playlist.id)

      prune

      expect(PlaylistVersion.exists?(stale.id)).to be(true)
    end

    it "clears the cursor once a sweep reaches the end" do
      with_stale_version
      PlaylistVersions::SweepCursor.write(playlist.id)

      prune

      expect(PlaylistVersions::SweepCursor.read).to eq(0)
    end

    it "prunes the skipped playlist on the run after the cursor clears" do
      stale = with_stale_version
      PlaylistVersions::SweepCursor.write(playlist.id)

      prune
      prune

      expect(PlaylistVersion.exists?(stale.id)).to be(false)
    end
  end

  # BatchPlan's own spec covers the packing. This is the wiring: the track counts the
  # pruner feeds it are the ones the candidates actually carry, and the batches it
  # returns are what BatchDelete receives.
  describe "sizing a batch by the rows it will delete" do
    it "hands BatchDelete the batches the plan called for" do
      stub_const("#{PlaylistVersions::BatchPlan}::TRACK_BUDGET", 4)
      batched = []
      allow(PlaylistVersions::BatchDelete).to receive(:new).and_wrap_original do |original, ids|
        batched << ids
        original.call(ids)
      end
      first = version(1, tracks: 3)
      second = version(2, tracks: 3)
      (3..5).each { |n| version(n) }

      expect { prune }.to change(PlaylistVersion, :count).by(-2)
      expect(batched).to eq([[first.id], [second.id]])
    end
  end

  describe "standing down" do
    it "does nothing while a scheduled run is live" do
      with_stale_version
      create(:scheduled_run, :running)

      expect { prune }.not_to change(PlaylistVersion, :count)
    end

    it "reports that it skipped" do
      create(:scheduled_run, :running)

      expect(prune).to have_attributes(skipped: true)
    end

    it "runs once the scheduled run has finished" do
      with_stale_version
      create(:scheduled_run, :completed)

      expect(prune.versions).to eq(1)
    end
  end

  describe "a reference that lands after selection" do
    let(:smart_playlist) { create(:smart_playlist, :with_rules) }

    def once_during_selection
      fired = false
      allow(PlaylistVersions::PruneCandidates).to receive(:new).and_wrap_original do |original, *args, **kwargs|
        original.call(*args, **kwargs).tap do
          next if fired

          fired = true
          yield
        end
      end
    end

    it "spares a version pinned between selection and delete" do
      stale = with_stale_version
      once_during_selection do
        create(:push_session, :running, smart_playlist: smart_playlist, baseline_version: stale)
      end

      prune

      expect(PlaylistVersion.exists?(stale.id)).to be(true)
    end

    it "spares a version made current between selection and delete" do
      stale = with_stale_version
      once_during_selection { playlist.update!(current_version: stale) }

      prune

      expect(PlaylistVersion.exists?(stale.id)).to be(true)
    end
  end

  describe "a batch that conflicts anyway" do
    before do
      allow(Rails.logger).to receive(:warn)
      allow(PlaylistVersion).to receive(:where).and_call_original
    end

    def raise_on_delete
      relation = instance_double(ActiveRecord::Relation)
      allow(relation).to receive(:delete_all).and_raise(ActiveRecord::InvalidForeignKey, "still referenced")
      allow(PlaylistVersion).to receive(:where).with(id: instance_of(Array)).and_return(relation)
    end

    it "rolls the batch back rather than losing the tick" do
      stale = with_stale_version(tracks: 2)
      raise_on_delete

      expect { prune }.not_to raise_error
      expect(PlaylistVersionTrack.where(playlist_version_id: stale.id).count).to eq(2)
    end

    it "counts and logs the conflict" do
      with_stale_version
      raise_on_delete

      expect(prune.conflicts).to eq(1)
      expect(Rails.logger).to have_received(:warn).with(/conflicted/)
    end
  end
end
