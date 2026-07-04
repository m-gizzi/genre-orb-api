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

  describe ".create_for_sync!" do
    let(:playlist) { create(:playlist) }

    it "creates a version with version_number 1 for new playlist" do
      version = described_class.create_for_sync!(playlist)
      expect(version.version_number).to eq(1)
      expect(version.track_count).to eq(0)
    end

    it "increments version number for existing versions" do
      create(:playlist_version, playlist: playlist, version_number: 1)
      version = described_class.create_for_sync!(playlist)
      expect(version.version_number).to eq(2)
    end
  end

  describe "#ordered_tracks" do
    let(:version) { create(:playlist_version, :with_tracks, tracks_count: 3) }

    it "returns tracks in position order" do
      positions = version.ordered_tracks.joins(:playlist_version_tracks)
                         .pluck("playlist_version_tracks.position")
      expect(positions).to eq([0, 1, 2])
    end
  end
end
