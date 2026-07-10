# frozen_string_literal: true

require "rails_helper"

RSpec.describe Spotify::PlaylistSyncSetup do
  let(:user) { create(:user) }
  let(:sync_session) { create(:sync_session, user: user) }
  let(:playlist) { create(:playlist, user: user, spotify_id: "playlist_123", last_synced_snapshot_id: "old_snapshot") }
  let(:playlist_session) do
    create(
      :sync_session_playlist,
      sync_session: sync_session,
      playlist: playlist,
      status: :pending,
    )
  end

  let(:adapter) { instance_spy(SpotifyAdapter) }
  let(:service) { described_class.new(playlist_session, adapter: adapter) }

  let(:track_items) do
    [
      {
        "track" => {
          "id" => "track_1",
          "name" => "Song One",
          "duration_ms" => 180_000,
          "track_number" => 1,
          "explicit" => false,
          "preview_url" => nil,
          "popularity" => 75,
          "artists" => [{ "id" => "artist_1", "name" => "Artist One" }],
          "album" => {
            "id" => "album_1",
            "name" => "Album One",
            "release_date" => "2023-05-15",
            "total_tracks" => 10,
            "images" => [{ "url" => "https://example.com/album.jpg" }],
            "artists" => [{ "id" => "artist_1", "name" => "Artist One" }],
          },
        },
      },
    ]
  end

  let(:playlist_response) do
    {
      "snapshot_id" => "new_snapshot",
      "tracks" => {
        "total" => 150,
        "items" => track_items,
      },
    }
  end

  before do
    create(:service_connection, user: user)
    allow(adapter).to receive(:playlist).and_return(playlist_response)
  end

  describe "#call" do
    it "returns skipped as false" do
      result = service.call
      expect(result.skipped?).to be(false)
    end

    it "creates a playlist version" do
      expect { service.call }.to change(PlaylistVersion, :count).by(1)
    end

    it "returns the created version" do
      result = service.call
      expect(result.version).to be_a(PlaylistVersion)
      expect(result.version.playlist).to eq(playlist)
    end

    it "returns remaining pages to fetch" do
      result = service.call
      expect(result.remaining_pages).to eq([1])
    end

    it "updates playlist_session status to fetching_pages" do
      service.call
      expect(playlist_session.reload.status).to eq("fetching_pages")
    end

    it "sets playlist_session total_pages" do
      service.call
      expect(playlist_session.reload.total_pages).to eq(2)
    end

    it "sets playlist_session completed_pages to 1 when first page has items" do
      service.call
      expect(playlist_session.reload.completed_pages).to eq(1)
    end

    it "upserts tracks from first page" do
      expect { service.call }.to change(Track, :count).by(1)
    end

    it "creates playlist version tracks" do
      expect { service.call }.to change(PlaylistVersionTrack, :count).by(1)
    end

    it "updates playlist last_seen_snapshot_id" do
      service.call
      expect(playlist.reload.last_seen_snapshot_id).to eq("new_snapshot")
    end

    context "when snapshot is unchanged" do
      let(:playlist) do
        create(:playlist, user: user, spotify_id: "playlist_123", last_synced_snapshot_id: "new_snapshot")
      end

      it "returns skipped as true" do
        result = service.call
        expect(result.skipped?).to be(true)
      end

      it "does not create a version" do
        expect { service.call }.not_to change(PlaylistVersion, :count)
      end

      it "marks playlist session as skipped" do
        service.call
        expect(playlist_session.reload.status).to eq("skipped")
      end
    end

    context "when playlist is single page" do
      let(:playlist_response) do
        {
          "snapshot_id" => "new_snapshot",
          "tracks" => {
            "total" => 50,
            "items" => track_items,
          },
        }
      end

      it "returns empty remaining_pages" do
        result = service.call
        expect(result.remaining_pages).to eq([])
      end

      it "completes the playlist session" do
        service.call
        expect(playlist_session.reload.status).to eq("completed")
      end

      it "does not double-count the single page" do
        service.call
        playlist_session.reload
        expect(playlist_session.completed_pages).to eq(playlist_session.total_pages)
      end
    end

    context "when playlist has many pages" do
      let(:playlist_response) do
        {
          "snapshot_id" => "new_snapshot",
          "tracks" => {
            "total" => 350,
            "items" => track_items,
          },
        }
      end

      it "returns all remaining pages" do
        result = service.call
        expect(result.remaining_pages).to eq([1, 2, 3])
      end

      it "sets correct total_pages" do
        service.call
        expect(playlist_session.reload.total_pages).to eq(4)
      end
    end

    context "when playlist is empty" do
      let(:playlist_response) do
        {
          "snapshot_id" => "new_snapshot",
          "tracks" => {
            "total" => 0,
            "items" => [],
          },
        }
      end

      it "sets completed_pages to 0" do
        service.call
        expect(playlist_session.reload.completed_pages).to eq(0)
      end

      it "returns empty remaining_pages" do
        result = service.call
        expect(result.remaining_pages).to eq([])
      end

      it "sets total_pages to 0" do
        service.call
        expect(playlist_session.reload.total_pages).to eq(0)
      end

      it "marks playlist session as completed" do
        service.call
        expect(playlist_session.reload.status).to eq("completed")
      end
    end

    context "with liked songs playlist" do
      let(:playlist) { create(:liked_songs_playlist, user: user) }
      let(:liked_songs_response) do
        {
          "total" => 200,
          "items" => track_items,
        }
      end

      before do
        allow(adapter).to receive(:liked_songs).and_return(liked_songs_response)
      end

      it "fetches via liked_songs endpoint" do
        service.call
        expect(adapter).to have_received(:liked_songs).with(limit: 50, offset: 0)
      end

      it "always processes (no snapshot check)" do
        result = service.call
        expect(result.skipped?).to be(false)
      end

      it "calculates pages based on liked songs page size" do
        # 200 tracks / 50 per page = 4 pages
        result = service.call
        expect(result.remaining_pages).to eq([1, 2, 3])
      end
    end
  end
end
