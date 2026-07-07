# frozen_string_literal: true

require "rails_helper"

RSpec.describe SyncSession do
  describe "#progress" do
    let(:session) { create(:sync_session) }

    it "returns zero progress when no playlists" do
      progress = session.progress
      expect(progress).to eq({ total: 0, completed: 0, skipped: 0, percent: 0 })
    end

    it "calculates progress correctly" do
      playlist1 = create(:playlist)
      playlist2 = create(:playlist)
      playlist3 = create(:playlist)

      create(:sync_session_playlist, :completed, sync_session: session, playlist: playlist1)
      create(:sync_session_playlist, :completed, sync_session: session, playlist: playlist2)
      create(:sync_session_playlist, :fetching, sync_session: session, playlist: playlist3)

      progress = session.progress
      expect(progress).to eq({ total: 3, completed: 2, skipped: 0, percent: 66 })
    end

    it "returns 100 percent when all complete" do
      playlist = create(:playlist)
      create(:sync_session_playlist, :completed, sync_session: session, playlist: playlist)

      progress = session.progress
      expect(progress).to eq({ total: 1, completed: 1, skipped: 0, percent: 100 })
    end

    it "counts skipped playlists in progress" do
      playlist1 = create(:playlist)
      playlist2 = create(:playlist)
      playlist3 = create(:playlist)

      create(:sync_session_playlist, :completed, sync_session: session, playlist: playlist1)
      create(:sync_session_playlist, :skipped, sync_session: session, playlist: playlist2)
      create(:sync_session_playlist, :fetching, sync_session: session, playlist: playlist3)

      progress = session.progress
      expect(progress).to eq({ total: 3, completed: 2, skipped: 1, percent: 66 })
    end
  end

  describe "#all_playlists_done?" do
    let(:session) { create(:sync_session) }

    it "returns true when no playlists" do
      expect(session.all_playlists_done?).to be(true)
    end

    it "returns true when all playlists are completed" do
      playlist1 = create(:playlist)
      playlist2 = create(:playlist)
      create(:sync_session_playlist, :completed, sync_session: session, playlist: playlist1)
      create(:sync_session_playlist, :completed, sync_session: session, playlist: playlist2)

      expect(session.all_playlists_done?).to be(true)
    end

    it "returns false when any playlist is not completed" do
      playlist1 = create(:playlist)
      playlist2 = create(:playlist)
      create(:sync_session_playlist, :completed, sync_session: session, playlist: playlist1)
      create(:sync_session_playlist, :fetching, sync_session: session, playlist: playlist2)

      expect(session.all_playlists_done?).to be(false)
    end

    it "returns true when all playlists are skipped" do
      playlist1 = create(:playlist)
      playlist2 = create(:playlist)
      create(:sync_session_playlist, :skipped, sync_session: session, playlist: playlist1)
      create(:sync_session_playlist, :skipped, sync_session: session, playlist: playlist2)

      expect(session.all_playlists_done?).to be(true)
    end

    it "returns true when mix of completed and skipped" do
      playlist1 = create(:playlist)
      playlist2 = create(:playlist)
      create(:sync_session_playlist, :completed, sync_session: session, playlist: playlist1)
      create(:sync_session_playlist, :skipped, sync_session: session, playlist: playlist2)

      expect(session.all_playlists_done?).to be(true)
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

    it "returns true for paused sessions" do
      session = build(:sync_session, status: :paused)
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

    it "returns false for cancelled sessions" do
      session = build(:sync_session, status: :cancelled)
      expect(session.active?).to be(false)
    end
  end
end
