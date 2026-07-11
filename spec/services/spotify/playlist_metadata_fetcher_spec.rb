# frozen_string_literal: true

require "rails_helper"

RSpec.describe Spotify::PlaylistMetadataFetcher do
  let(:user) { create(:user) }
  let(:adapter) { instance_double(SpotifyAdapter) }
  let(:service) { described_class.new(user) }

  before do
    create(:service_connection, user: user)
    allow(SpotifyAdapter).to receive(:new).and_return(adapter)
  end

  describe "#call" do
    let(:spotify_playlists) do
      [
        { "id" => "playlist_1", "name" => "My Playlist", "snapshot_id" => "snap1", "public" => true },
        { "id" => "playlist_2", "name" => "Another", "snapshot_id" => "snap2", "public" => false },
      ]
    end

    before do
      allow(adapter).to receive(:playlists)
        .with(limit: 50, offset: 0)
        .and_return({ "items" => spotify_playlists, "next" => nil })
      allow(adapter).to receive(:liked_songs)
        .with(limit: 1)
        .and_return({ "total" => 100 })
    end

    it "returns success result" do
      result = service.call
      expect(result.success?).to be(true)
    end

    it "creates playlists for the user" do
      expect { service.call }.to change { user.playlists.count }.by(3) # 2 regular + liked songs
    end

    it "upserts playlist data from Spotify" do
      service.call

      playlist = Playlist.find_by(spotify_id: "playlist_1")
      expect(playlist.name).to eq("My Playlist")
      expect(playlist.last_seen_snapshot_id).to eq("snap1")
      expect(playlist.is_public).to be(true)
      expect(playlist.available_on_spotify).to be(true)
    end

    it "creates liked songs playlist" do
      service.call

      liked = user.playlists.liked_songs.first
      expect(liked).to be_present
      expect(liked.name).to eq("Liked Songs")
    end

    it "updates user playlists_metadata_fetched_at" do
      service.call
      expect(user.reload.playlists_metadata_fetched_at).to be_within(1.second).of(Time.current)
    end

    context "when playlists span multiple pages" do
      let(:page1_playlists) do
        [{ "id" => "p1", "name" => "Page 1", "snapshot_id" => "s1", "public" => false }]
      end

      let(:page2_playlists) do
        [{ "id" => "p2", "name" => "Page 2", "snapshot_id" => "s2", "public" => false }]
      end

      before do
        allow(adapter).to receive(:playlists)
          .with(limit: 50, offset: 0)
          .and_return({ "items" => page1_playlists, "next" => "http://example.com/next" })
        allow(adapter).to receive(:playlists)
          .with(limit: 50, offset: 50)
          .and_return({ "items" => page2_playlists, "next" => nil })
      end

      it "fetches all pages" do
        service.call
        expect(Playlist.where(spotify_id: %w[p1 p2]).count).to eq(2)
      end
    end

    context "when playlist is removed from Spotify" do
      let!(:deleted_playlist) do
        create(:playlist, user: user, spotify_id: "deleted_playlist", available_on_spotify: true)
      end

      it "marks removed playlists as unavailable" do
        service.call
        expect(deleted_playlist.reload.available_on_spotify).to be(false)
      end
    end

    context "when user already has liked songs" do
      before do
        create(:liked_songs_playlist, user: user)
      end

      it "does not create duplicate liked songs" do
        expect { service.call }.not_to(change { LikedSongsPlaylist.where(user: user).count })
      end

      it "marks existing liked songs as available" do
        liked = user.playlists.liked_songs.first
        liked.update!(available_on_spotify: false)

        service.call
        expect(liked.reload.available_on_spotify).to be(true)
      end
    end

    context "when API fails" do
      before do
        allow(adapter).to receive(:playlists).and_raise(StandardError, "API error")
      end

      it "returns failure result" do
        result = service.call
        expect(result.success?).to be(false)
        expect(result.error).to eq("API error")
      end

      it "records the error on the user so it can be surfaced" do
        service.call
        expect(user.reload.playlists_metadata_error).to eq("API error")
      end
    end

    context "when rate limited" do
      before do
        allow(adapter).to receive(:playlists)
          .and_raise(SpotifyAdapter::RateLimitError.new(retry_after: 30, user_id: user.id))
      end

      it "re-raises so the job can pause and re-enqueue" do
        expect { service.call }.to raise_error(SpotifyAdapter::RateLimitError)
      end
    end

    it "clears a previous error after a successful fetch" do
      user.update!(playlists_metadata_error: "stale error")
      service.call
      expect(user.reload.playlists_metadata_error).to be_nil
    end
  end
end
