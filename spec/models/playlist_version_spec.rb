# frozen_string_literal: true

require "rails_helper"

RSpec.describe PlaylistVersion do
  describe "scopes" do
    let(:playlist) { create(:playlist) }

    before do
      create(:playlist_version, playlist: playlist, version_number: 1)
      create(:playlist_version, playlist: playlist, version_number: 3)
      create(:playlist_version, playlist: playlist, version_number: 2)
    end

    describe ".recent" do
      it "orders by version_number descending" do
        expect(described_class.recent.pluck(:version_number)).to eq([3, 2, 1])
      end
    end

    describe ".latest" do
      it "returns the highest version" do
        expect(described_class.latest.version_number).to eq(3)
      end
    end
  end

  describe ".create_snapshot" do
    let(:playlist) { create(:playlist, :with_tracks, tracks_count: 5) }

    it "creates a version with current track IDs" do
      version = described_class.create_snapshot(playlist)
      expect(version.track_ids.count).to eq(5)
      expect(version.track_count).to eq(5)
    end

    it "increments version number" do
      first = described_class.create_snapshot(playlist)
      expect(first.version_number).to eq(1)

      second = described_class.create_snapshot(playlist)
      expect(second.version_number).to eq(2)
    end

    it "preserves track order" do
      expected_order = playlist.playlist_tracks.order(:position).pluck(:track_id)
      version = described_class.create_snapshot(playlist)
      expect(version.track_ids).to eq(expected_order)
    end
  end
end
