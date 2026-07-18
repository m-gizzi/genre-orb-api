# frozen_string_literal: true

require "rails_helper"

RSpec.describe Playlist do
  describe "#destroy" do
    it "destroys a playlist that has a current_version set (no circular FK violation)" do
      playlist = create(:playlist, :with_tracks)
      expect(playlist.current_version_id).to be_present

      expect { playlist.destroy! }.to change(described_class, :count).by(-1)
    end

    it "destroys a playlist referenced by a sync_session_playlist's version" do
      playlist = create(:playlist, :with_tracks)
      create(:sync_session_playlist, playlist: playlist, playlist_version: playlist.current_version)

      expect { playlist.destroy! }.not_to raise_error
    end

    it "allows the owning user to be destroyed after a completed sync" do
      user = create(:user)
      playlist = create(:playlist, :with_tracks, user: user)
      create(:sync_session_playlist, playlist: playlist, playlist_version: playlist.current_version)

      expect { user.destroy! }.to change(described_class, :count).by(-1)
    end
  end

  describe "#current_version_tracks" do
    it "returns the current version's tracks in position order" do
      playlist = create(:playlist)
      version = create(:playlist_version, :current, playlist: playlist)
      first = create(:track)
      second = create(:track)
      create(:playlist_version_track, playlist_version: version, track: second, position: 1)
      create(:playlist_version_track, playlist_version: version, track: first, position: 0)

      expect(playlist.current_version_tracks.map(&:track)).to eq([first, second])
    end

    it "returns none when there is no current version" do
      expect(create(:playlist).current_version_tracks).to be_empty
    end
  end
end
