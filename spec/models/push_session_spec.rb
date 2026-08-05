# frozen_string_literal: true

require "rails_helper"

RSpec.describe PushSession do
  describe "associations" do
    it { is_expected.to belong_to(:smart_playlist) }
    it { is_expected.to belong_to(:playlist_version).optional }
  end

  describe "scopes" do
    it "counts pending and running sessions as active" do
      pending_session = create(:push_session)
      running_session = create(:push_session, :running)
      create(:push_session, :completed)

      expect(described_class.active).to contain_exactly(pending_session, running_session)
    end

    it "orders recent newest first" do
      older = create(:push_session, :completed, created_at: 2.days.ago)
      newer = create(:push_session, :completed, created_at: 1.day.ago)

      expect(described_class.recent.first(2)).to eq([newer, older])
    end
  end

  describe "the unique active index" do
    it "rejects a second active push for the same smart playlist" do
      session = create(:push_session, :running)

      expect { create(:push_session, smart_playlist: session.smart_playlist) }
        .to raise_error(ActiveRecord::RecordNotUnique)
    end

    it "allows a new push once the previous one finished" do
      session = create(:push_session, :completed)

      expect { create(:push_session, smart_playlist: session.smart_playlist) }.not_to raise_error
    end

    it "allows concurrent pushes for different smart playlists" do
      create(:push_session, :running)

      expect { create(:push_session, :running) }.not_to raise_error
    end
  end

  describe "#progress" do
    it "sums both phases" do
      session = create(:push_session, :with_batches, remove_batches: 2, add_batches: 3,
                                                     completed_remove_batches: 2, completed_add_batches: 1,)

      expect(session.progress).to eq(total: 5, completed: 3, percent: 60)
    end

    it "reports complete when there is nothing to do" do
      expect(create(:push_session).progress).to eq(total: 0, completed: 0, percent: 100)
    end
  end

  describe "#remove_batch_completed!" do
    it "returns false until the last batch of the phase" do
      session = create(:push_session, :with_batches, remove_batches: 2)

      expect(session.remove_batch_completed!("snap_1")).to be(false)
      expect(session.remove_batch_completed!("snap_2")).to be(true)
      expect(session.reload.completed_remove_batches).to eq(2)
    end

    it "records the snapshot from the response" do
      session = create(:push_session, :with_batches, remove_batches: 1)

      session.remove_batch_completed!("snap_1")

      expect(session.reload.spotify_snapshot_id).to eq("snap_1")
    end

    it "keeps the previous snapshot when a response carries none" do
      session = create(:push_session, :with_batches, remove_batches: 2, spotify_snapshot_id: "snap_1")

      session.remove_batch_completed!(nil)

      expect(session.reload.spotify_snapshot_id).to eq("snap_1")
    end
  end

  describe "#add_batch_completed!" do
    it "counts the add phase independently of the remove phase" do
      session = create(:push_session, :with_batches, remove_batches: 2, add_batches: 1)

      expect(session.add_batch_completed!("snap_1")).to be(true)
      expect(session.reload.completed_remove_batches).to eq(0)
    end
  end
end
