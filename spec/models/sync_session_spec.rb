# frozen_string_literal: true

require "rails_helper"

RSpec.describe SyncSession do
  describe "#progress" do
    it "returns zero progress when no playlists" do
      session = create(:sync_session, total_playlists: 0)

      progress = session.progress
      expect(progress).to eq({ total: 0, completed: 0, skipped: 0, percent: 0 })
    end

    it "calculates progress correctly using cached columns" do
      session = create(:sync_session, total_playlists: 3, completed_playlists: 2, skipped_playlists: 0)

      progress = session.progress
      expect(progress).to eq({ total: 3, completed: 2, skipped: 0, percent: 66 })
    end

    it "returns 100 percent when all complete" do
      session = create(:sync_session, total_playlists: 1, completed_playlists: 1, skipped_playlists: 0)

      progress = session.progress
      expect(progress).to eq({ total: 1, completed: 1, skipped: 0, percent: 100 })
    end

    it "counts skipped playlists in progress" do
      session = create(:sync_session, total_playlists: 3, completed_playlists: 1, skipped_playlists: 1)

      progress = session.progress
      expect(progress).to eq({ total: 3, completed: 2, skipped: 1, percent: 66 })
    end
  end

  describe "#all_playlists_done?" do
    it "returns false when no playlists (total is 0)" do
      session = create(:sync_session, total_playlists: 0)

      expect(session.all_playlists_done?).to be(false)
    end

    it "returns true when all playlists are completed" do
      session = create(:sync_session, total_playlists: 2, completed_playlists: 2)

      expect(session.all_playlists_done?).to be(true)
    end

    it "returns false when any playlist is not completed" do
      session = create(:sync_session, total_playlists: 2, completed_playlists: 1)

      expect(session.all_playlists_done?).to be(false)
    end

    it "returns true when all playlists are skipped" do
      session = create(:sync_session, total_playlists: 2, skipped_playlists: 2)

      expect(session.all_playlists_done?).to be(true)
    end

    it "returns true when mix of completed and skipped" do
      session = create(:sync_session, total_playlists: 2, completed_playlists: 1, skipped_playlists: 1)

      expect(session.all_playlists_done?).to be(true)
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
