# frozen_string_literal: true

require "rails_helper"

RSpec.describe Spotify::PlaylistSyncStrategy do
  describe "#page_size" do
    it "returns 100 for regular playlists" do
      playlist = build(:playlist)
      strategy = described_class.new(playlist)

      expect(strategy.page_size).to eq(100)
    end

    it "returns 50 for Liked Songs" do
      playlist = build(:liked_songs_playlist)
      strategy = described_class.new(playlist)

      expect(strategy.page_size).to eq(50)
    end
  end

  describe "#snapshot_unchanged?" do
    it "returns false for Liked Songs regardless of snapshot" do
      playlist = build(:liked_songs_playlist, last_synced_snapshot_id: "snap1")
      strategy = described_class.new(playlist)

      expect(strategy.snapshot_unchanged?("snap1")).to be(false)
    end

    it "returns false when last_synced_snapshot_id is nil" do
      playlist = build(:playlist, last_synced_snapshot_id: nil)
      strategy = described_class.new(playlist)

      expect(strategy.snapshot_unchanged?("snap1")).to be(false)
    end

    it "returns true when snapshots match" do
      playlist = build(:playlist, last_synced_snapshot_id: "snap1")
      strategy = described_class.new(playlist)

      expect(strategy.snapshot_unchanged?("snap1")).to be(true)
    end

    it "returns false when snapshots differ" do
      playlist = build(:playlist, last_synced_snapshot_id: "snap1")
      strategy = described_class.new(playlist)

      expect(strategy.snapshot_unchanged?("snap2")).to be(false)
    end
  end

  describe "#fetch_tracks_page" do
    let(:adapter) { instance_double(SpotifyAdapter) }

    context "with regular playlist" do
      let(:playlist) { build(:playlist, :with_spotify) }
      let(:strategy) { described_class.new(playlist) }

      it "calls playlist_tracks on the adapter" do
        expect(adapter).to receive(:playlist_tracks)
          .with(playlist.spotify_id, limit: 100, offset: 0)
          .and_return({ "items" => [] })

        strategy.fetch_tracks_page(adapter, limit: 100, offset: 0)
      end
    end

    context "with Liked Songs playlist" do
      let(:playlist) { build(:liked_songs_playlist) }
      let(:strategy) { described_class.new(playlist) }

      it "calls liked_songs on the adapter" do
        expect(adapter).to receive(:liked_songs)
          .with(limit: 50, offset: 0)
          .and_return({ "items" => [] })

        strategy.fetch_tracks_page(adapter, limit: 50, offset: 0)
      end

      it "clamps the limit to page_size" do
        expect(adapter).to receive(:liked_songs)
          .with(limit: 50, offset: 0)
          .and_return({ "items" => [] })

        strategy.fetch_tracks_page(adapter, limit: 100, offset: 0)
      end

      it "clamps the limit to at least 1" do
        expect(adapter).to receive(:liked_songs)
          .with(limit: 1, offset: 0)
          .and_return({ "items" => [] })

        strategy.fetch_tracks_page(adapter, limit: 0, offset: 0)
      end
    end
  end
end
