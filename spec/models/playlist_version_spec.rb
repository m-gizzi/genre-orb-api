# frozen_string_literal: true

require "rails_helper"

RSpec.describe PlaylistVersion do
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
end
