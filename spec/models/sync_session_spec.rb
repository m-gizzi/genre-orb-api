# frozen_string_literal: true

require "rails_helper"

RSpec.describe SyncSession do
  describe "#progress" do
    it "returns zero progress when no playlists" do
      session = create(:sync_session, total_playlists: 0)

      progress = session.progress
      expect(progress).to eq({ total: 0, completed: 0, skipped: 0, failed: 0, percent: 0 })
    end

    it "calculates progress correctly using cached columns" do
      session = create(:sync_session, total_playlists: 3, completed_playlists: 2, skipped_playlists: 0)

      progress = session.progress
      expect(progress).to eq({ total: 3, completed: 2, skipped: 0, failed: 0, percent: 66 })
    end

    it "returns 100 percent when all complete" do
      session = create(:sync_session, total_playlists: 1, completed_playlists: 1, skipped_playlists: 0)

      progress = session.progress
      expect(progress).to eq({ total: 1, completed: 1, skipped: 0, failed: 0, percent: 100 })
    end

    it "counts skipped playlists in progress" do
      session = create(:sync_session, total_playlists: 3, completed_playlists: 1, skipped_playlists: 1)

      progress = session.progress
      expect(progress).to eq({ total: 3, completed: 2, skipped: 1, failed: 0, percent: 66 })
    end

    it "counts failed playlists toward percent so the bar reaches 100" do
      session = create(:sync_session, total_playlists: 2, completed_playlists: 1, failed_playlists: 1)

      progress = session.progress
      expect(progress).to eq({ total: 2, completed: 1, skipped: 0, failed: 1, percent: 100 })
    end
  end

  describe "#reconcile!" do
    it "marks the session completed when every playlist succeeded" do
      session = create(:sync_session, :running, total_playlists: 2)
      create(:sync_session_playlist, :completed, sync_session: session)
      create(:sync_session_playlist, :skipped, sync_session: session)

      session.reconcile!

      expect(session.reload.status).to eq("completed")
      expect(session.completed_at).to be_present
    end

    it "marks the session completed_with_errors on a mix of success and failure" do
      session = create(:sync_session, :running, total_playlists: 2)
      create(:sync_session_playlist, :completed, sync_session: session)
      create(:sync_session_playlist, :failed, sync_session: session)

      session.reconcile!

      expect(session.reload.status).to eq("completed_with_errors")
    end

    it "marks the session failed when every playlist failed" do
      session = create(:sync_session, :running, total_playlists: 2)
      create(:sync_session_playlist, :failed, sync_session: session)
      create(:sync_session_playlist, :failed, sync_session: session)

      session.reconcile!

      expect(session.reload.status).to eq("failed")
    end

    it "stays active while any playlist is still in flight" do
      session = create(:sync_session, :running, total_playlists: 2)
      create(:sync_session_playlist, :completed, sync_session: session)
      create(:sync_session_playlist, :fetching, sync_session: session)

      session.reconcile!

      expect(session.reload.status).to eq("running")
    end

    it "does not re-transition an already-terminal session" do
      session = create(:sync_session, :completed, total_playlists: 1)
      create(:sync_session_playlist, :failed, sync_session: session)

      session.reconcile!

      expect(session.reload.status).to eq("completed")
    end
  end

  describe "#increment_completed!" do
    it "atomically increments completed_playlists" do
      session = create(:sync_session, total_playlists: 2, completed_playlists: 0)

      session.increment_completed!

      expect(session.reload.completed_playlists).to eq(1)
    end
  end

  describe "#increment_skipped!" do
    it "atomically increments skipped_playlists" do
      session = create(:sync_session, total_playlists: 2, skipped_playlists: 0)

      session.increment_skipped!

      expect(session.reload.skipped_playlists).to eq(1)
    end
  end

  describe "#increment_failed!" do
    it "atomically increments failed_playlists" do
      session = create(:sync_session, total_playlists: 2, failed_playlists: 0)

      session.increment_failed!

      expect(session.reload.failed_playlists).to eq(1)
    end
  end

  describe "#active?" do
    it "returns true for pending sessions" do
      session = build(:sync_session, status: :pending)
      expect(session.active?).to be(true)
    end

    it "returns true for running sessions" do
      session = build(:sync_session, :running)
      expect(session.active?).to be(true)
    end

    it "returns false for completed sessions" do
      session = build(:sync_session, :completed)
      expect(session.active?).to be(false)
    end

    it "returns false for failed sessions" do
      session = build(:sync_session, :failed)
      expect(session.active?).to be(false)
    end
  end
end
