# frozen_string_literal: true

require "rails_helper"

RSpec.describe Playlist do
  describe "#snapshot_unchanged?" do
    it "returns false for Liked Songs" do
      playlist = build(:liked_songs_playlist, last_synced_snapshot_id: "snap1")
      expect(playlist.snapshot_unchanged?("snap1")).to be(false)
    end

    it "returns false when last_synced_snapshot_id is nil" do
      playlist = build(:playlist, last_synced_snapshot_id: nil)
      expect(playlist.snapshot_unchanged?("snap1")).to be(false)
    end

    it "returns true when snapshots match" do
      playlist = build(:playlist, last_synced_snapshot_id: "snap1")
      expect(playlist.snapshot_unchanged?("snap1")).to be(true)
    end

    it "returns false when snapshots differ" do
      playlist = build(:playlist, last_synced_snapshot_id: "snap1")
      expect(playlist.snapshot_unchanged?("snap2")).to be(false)
    end
  end
end
