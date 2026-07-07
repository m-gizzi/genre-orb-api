# frozen_string_literal: true

require "rails_helper"

RSpec.describe Spotify::PlaylistPageFetcher do
  let(:user) { create(:user) }
  let(:sync_session) { create(:sync_session, user: user) }
  let(:playlist) { create(:playlist, user: user, spotify_id: "playlist_123") }
  let(:version) { create(:playlist_version, playlist: playlist) }
  let(:playlist_session) do
    create(
      :sync_session_playlist,
      sync_session: sync_session,
      playlist: playlist,
      playlist_version: version,
      status: :fetching_pages,
      total_pages: 3,
      completed_pages: 0,
    )
  end

  let(:adapter) { instance_double(SpotifyAdapter) }
  let(:service) { described_class.new(playlist_session, page: page, adapter: adapter) }
  let(:page) { 1 }

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

  let(:api_response) { { "items" => track_items } }

  before do
    create(:service_connection, user: user)
    allow(adapter).to receive(:playlist_tracks).and_return(api_response)
  end

  describe "#call" do
    it "returns success result" do
      result = service.call
      expect(result.success?).to be(true)
    end

    it "fetches tracks page with correct offset" do
      service.call
      expect(adapter).to have_received(:playlist_tracks).with("playlist_123", limit: 100, offset: 100)
    end

    it "upserts tracks" do
      expect { service.call }.to change(Track, :count).by(1)
    end

    it "creates playlist version tracks" do
      expect { service.call }.to change(PlaylistVersionTrack, :count).by(1)
    end

    it "increments completed_pages on playlist session" do
      expect { service.call }.to change { playlist_session.reload.completed_pages }.by(1)
    end

    context "when page is first page (page 0)" do
      let(:page) { 0 }

      it "fetches with zero offset" do
        service.call
        expect(adapter).to have_received(:playlist_tracks).with("playlist_123", limit: 100, offset: 0)
      end
    end

    context "when this is the final page" do
      let(:playlist_session) do
        create(
          :sync_session_playlist,
          sync_session: sync_session,
          playlist: playlist,
          playlist_version: version,
          status: :fetching_pages,
          total_pages: 2,
          completed_pages: 1,
        )
      end

      it "returns sync_completed as true" do
        result = service.call
        expect(result.sync_completed?).to be(true)
      end

      it "completes the playlist session" do
        service.call
        expect(playlist_session.reload.status).to eq("completed")
      end
    end

    context "when more pages remain" do
      let(:playlist_session) do
        create(
          :sync_session_playlist,
          sync_session: sync_session,
          playlist: playlist,
          playlist_version: version,
          status: :fetching_pages,
          total_pages: 5,
          completed_pages: 1,
        )
      end

      it "returns sync_completed as false" do
        result = service.call
        expect(result.sync_completed?).to be(false)
      end

      it "does not complete the playlist session" do
        service.call
        expect(playlist_session.reload.status).to eq("fetching_pages")
      end
    end

    context "with empty items response" do
      let(:api_response) { { "items" => [] } }

      it "returns success" do
        result = service.call
        expect(result.success?).to be(true)
      end

      it "does not create tracks" do
        expect { service.call }.not_to change(Track, :count)
      end

      it "still increments completed_pages" do
        expect { service.call }.to change { playlist_session.reload.completed_pages }.by(1)
      end
    end

    context "with nil items in response" do
      let(:api_response) { {} }

      it "handles nil items gracefully" do
        result = service.call
        expect(result.success?).to be(true)
      end
    end

    context "with liked songs playlist" do
      let(:playlist) { create(:liked_songs_playlist, user: user) }

      before do
        allow(adapter).to receive(:liked_songs).and_return(api_response)
      end

      it "fetches tracks via liked songs adapter method" do
        service.call
        # LikedSongsPlaylist uses 50 as page size, so offset for page 1 is 50
        expect(adapter).to have_received(:liked_songs).with(limit: 50, offset: 50)
      end
    end
  end
end
