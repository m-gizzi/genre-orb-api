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

  describe "smart playlist targets" do
    it "turns sync on when the playlist becomes rule-managed" do
      target = create(:playlist, :with_spotify, sync_enabled: false)

      create(:smart_playlist, target_playlist: target)

      expect(target.reload.sync_enabled).to be(true)
    end

    it "refuses to turn sync off for a rule-managed playlist" do
      target = create(:smart_playlist).target_playlist

      target.sync_enabled = false

      expect(target).not_to be_valid
      expect(target.errors[:sync_enabled])
        .to include("cannot be turned off for a smart playlist's target")
    end

    it "leaves sync_enabled alone for a regular playlist" do
      playlist = create(:playlist, sync_enabled: true)

      playlist.update!(sync_enabled: false)

      expect(playlist.reload.sync_enabled).to be(false)
    end

    it "destroys the owning user even when a playlist is used as a smart playlist source" do
      smart_playlist = create(:smart_playlist)
      user = smart_playlist.target_playlist.user

      expect { user.destroy! }.to change(SmartPlaylist, :count).by(-1)
      expect(described_class.where(user_id: user.id)).to be_empty
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
