# frozen_string_literal: true

require "rails_helper"

# These cover the re-validation BatchDelete does under the lock, plus its reporting.
# They do not cover SKIP LOCKED itself: a transactional example runs on one connection,
# so nothing here can genuinely hold a row against the sweep.
RSpec.describe PlaylistVersions::BatchDelete do
  let(:playlist) { create(:playlist) }
  let(:smart_playlist) { create(:smart_playlist, :with_rules) }

  def version(number, tracks: 0)
    create(:playlist_version, playlist: playlist, version_number: number).tap do |built|
      tracks.times { |i| create(:playlist_version_track, playlist_version: built, position: i) }
    end
  end

  def delete_batch(*versions)
    described_class.new(versions.map(&:id)).call
  end

  it "deletes the versions it was handed" do
    stale = version(1)

    delete_batch(stale)

    expect(PlaylistVersion.exists?(stale.id)).to be(false)
  end

  it "deletes their tracks and counts both" do
    stale = version(1, tracks: 3)

    expect(delete_batch(stale)).to have_attributes(versions: 1, tracks: 3, conflicted: false, contended: 0)
  end

  it "spares a version that became current since selection" do
    stale = version(1)
    playlist.update!(current_version: stale)

    expect(delete_batch(stale)).to have_attributes(versions: 0, tracks: 0)
    expect(PlaylistVersion.exists?(stale.id)).to be(true)
  end

  it "spares a version a live session pinned since selection" do
    stale = version(1)
    create(:push_session, :running, smart_playlist: smart_playlist, baseline_version: stale)

    expect(delete_batch(stale)).to have_attributes(versions: 0)
    expect(PlaylistVersion.exists?(stale.id)).to be(true)
  end

  it "releases a terminal session's pointer and deletes the version" do
    stale = version(1)
    session = create(:push_session, :completed, smart_playlist: smart_playlist, playlist_version: stale)

    delete_batch(stale)

    expect(session.reload.playlist_version_id).to be_nil
    expect(PlaylistVersion.exists?(stale.id)).to be(false)
  end

  it "deletes the rest of the batch when one member is spared" do
    spared = version(1)
    doomed = version(2)
    playlist.update!(current_version: spared)

    expect(delete_batch(spared, doomed)).to have_attributes(versions: 1)
    expect(PlaylistVersion.exists?(spared.id)).to be(true)
    expect(PlaylistVersion.exists?(doomed.id)).to be(false)
  end

  describe "reporting contention" do
    it "counts an id that was gone before the lock" do
      stale = version(1)
      missing = stale.id + 10_000

      expect(described_class.new([stale.id, missing]).call).to have_attributes(versions: 1, contended: 1)
    end

    it "distinguishes a fully contended batch from an empty one" do
      stale = version(1)

      contended = described_class.new([stale.id + 10_000]).call
      spared = described_class.new([create(:playlist_version, :current).id]).call

      expect(contended).to have_attributes(versions: 0, contended: 1)
      expect(spared).to have_attributes(versions: 0, contended: 0)
    end
  end

  describe "a conflict the re-read did not catch" do
    before { allow(Rails.logger).to receive(:warn) }

    def raise_on_delete(error)
      relation = instance_double(ActiveRecord::Relation)
      allow(relation).to receive(:delete_all).and_raise(error, "boom")
      allow(PlaylistVersion).to receive(:where).and_call_original
      allow(PlaylistVersion).to receive(:where).with(id: instance_of(Array)).and_return(relation)
    end

    # Every one of these costs the batch. None may cost the sweep, which has no rescue
    # between here and the job's blanket one.
    [
      ActiveRecord::InvalidForeignKey,
      ActiveRecord::LockWaitTimeout,
      ActiveRecord::Deadlocked,
      ActiveRecord::QueryCanceled,
    ].each do |error|
      it "rolls back and reports a conflict on #{error}" do
        stale = version(1, tracks: 2)
        raise_on_delete(error)

        expect(described_class.new([stale.id]).call).to have_attributes(versions: 0, conflicted: true)
        expect(PlaylistVersionTrack.where(playlist_version_id: stale.id).count).to eq(2)
      end
    end
  end
end
