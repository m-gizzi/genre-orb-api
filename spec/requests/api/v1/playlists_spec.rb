# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::Playlists" do
  let(:user) { create(:user) }

  describe "GET /api/v1/playlists" do
    context "when not authenticated" do
      it "returns 401 unauthorized" do
        get "/api/v1/playlists"
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context "when authenticated" do
      before { sign_in user }

      it "returns 200 OK" do
        get "/api/v1/playlists"
        expect(response).to have_http_status(:ok)
      end

      it "returns only user's playlists in a data/meta envelope" do
        my_playlist = create(:playlist, user: user, available_on_spotify: true)
        create(:playlist, available_on_spotify: true)

        get "/api/v1/playlists"

        expect(response.parsed_body["data"].pluck("id")).to contain_exactly(my_playlist.id)
        expect(response.parsed_body["meta"]).to include("total" => 1)
      end

      it "returns only available playlists" do
        available = create(:playlist, user: user, available_on_spotify: true)
        create(:playlist, user: user, available_on_spotify: false)

        get "/api/v1/playlists"

        expect(response.parsed_body["data"].pluck("id")).to contain_exactly(available.id)
      end

      it "orders playlists by name" do
        create(:playlist, user: user, name: "Zebra", available_on_spotify: true)
        create(:playlist, user: user, name: "Alpha", available_on_spotify: true)
        create(:playlist, user: user, name: "Middle", available_on_spotify: true)

        get "/api/v1/playlists"

        expect(response.parsed_body["data"].pluck("name")).to eq(%w[Alpha Middle Zebra])
      end

      it "sorts by name descending" do
        create(:playlist, user: user, name: "Alpha", available_on_spotify: true)
        create(:playlist, user: user, name: "Zebra", available_on_spotify: true)

        get "/api/v1/playlists", params: { sort: "name", order: "desc" }

        expect(response.parsed_body["data"].pluck("name")).to eq(%w[Zebra Alpha])
      end

      it "sorts by last_synced_at descending (nulls last)" do
        recent = create(:playlist, user: user, name: "Recent", available_on_spotify: true,
                                   last_synced_at: 1.hour.ago,)
        old = create(:playlist, user: user, name: "Old", available_on_spotify: true,
                                last_synced_at: 3.days.ago,)
        never = create(:playlist, user: user, name: "Never", available_on_spotify: true,
                                  last_synced_at: nil,)

        get "/api/v1/playlists", params: { sort: "last_synced_at", order: "desc" }

        expect(response.parsed_body["data"].pluck("id")).to eq([recent.id, old.id, never.id])
      end

      it "sorts by track_count descending" do
        big = create(:playlist, :with_tracks, tracks_count: 5, user: user, name: "Big",
                                              available_on_spotify: true,)
        small = create(:playlist, :with_tracks, tracks_count: 1, user: user, name: "Small",
                                                available_on_spotify: true,)

        get "/api/v1/playlists", params: { sort: "track_count", order: "desc" }

        expect(response.parsed_body["data"].pluck("id")).to eq([big.id, small.id])
      end

      it "returns playlist attributes" do
        playlist = create(:playlist, :with_spotify, :sync_enabled, user: user, available_on_spotify: true)

        get "/api/v1/playlists"
        body = response.parsed_body["data"].first

        expect(body["id"]).to eq(playlist.id)
        expect(body["name"]).to eq(playlist.name)
        expect(body["spotify_id"]).to eq(playlist.spotify_id)
        expect(body["sync_enabled"]).to be(true)
        expect(body["available_on_spotify"]).to be(true)
      end

      it "returns track_count from current version" do
        create(:playlist, :with_tracks, tracks_count: 5, user: user, available_on_spotify: true)

        get "/api/v1/playlists"
        expect(response.parsed_body["data"].first["track_count"]).to eq(5)
      end

      it "returns is_liked_songs attribute" do
        create(:liked_songs_playlist, user: user)

        get "/api/v1/playlists"
        expect(response.parsed_body["data"].first["is_liked_songs"]).to be(true)
      end
    end
  end

  describe "GET /api/v1/playlists/:id" do
    before { sign_in user }

    it "returns the playlist with a current_version summary" do
      playlist = create(:playlist, :with_tracks, tracks_count: 3, user: user, available_on_spotify: true)

      get "/api/v1/playlists/#{playlist.id}"
      data = response.parsed_body["data"]

      expect(response).to have_http_status(:ok)
      expect(data["id"]).to eq(playlist.id)
      expect(data["track_count"]).to eq(3)
      expect(data["current_version"]).to include(
        "track_count" => 3,
        "version_number" => playlist.current_version.version_number,
      )
    end

    it "returns 404 for another user's playlist" do
      get "/api/v1/playlists/#{create(:playlist).id}"
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "GET /api/v1/playlists/:id/tracks" do
    before { sign_in user }

    it "returns the playlist's tracks in position order with a meta envelope" do
      playlist = create(:playlist, user: user, available_on_spotify: true)
      version = create(:playlist_version, playlist: playlist)
      playlist.update!(current_version: version)
      first = create(:track, title: "First")
      second = create(:track, title: "Second")
      create(:playlist_version_track, playlist_version: version, track: second, position: 1)
      create(:playlist_version_track, playlist_version: version, track: first, position: 0)

      get "/api/v1/playlists/#{playlist.id}/tracks"

      expect(response.parsed_body["data"].pluck("id")).to eq([first.id, second.id])
      expect(response.parsed_body["meta"]).to include("total" => 2)
    end

    it "returns an empty list when the playlist has no current version" do
      playlist = create(:playlist, user: user, available_on_spotify: true)

      get "/api/v1/playlists/#{playlist.id}/tracks"

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["data"]).to eq([])
      expect(response.parsed_body["meta"]["total"]).to eq(0)
    end

    it "returns 404 for another user's playlist" do
      get "/api/v1/playlists/#{create(:playlist).id}/tracks"
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "PATCH /api/v1/playlists/:id" do
    let(:playlist) { create(:playlist, user: user) }

    context "when not authenticated" do
      it "returns 401 unauthorized" do
        patch "/api/v1/playlists/#{playlist.id}", params: { playlist: { sync_enabled: true } }
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context "when authenticated" do
      before { sign_in user }

      it "returns 200 OK" do
        patch "/api/v1/playlists/#{playlist.id}", params: { playlist: { sync_enabled: true } }
        expect(response).to have_http_status(:ok)
      end

      it "updates sync_enabled" do
        patch "/api/v1/playlists/#{playlist.id}", params: { playlist: { sync_enabled: true } }
        expect(playlist.reload.sync_enabled).to be(true)
      end

      it "returns the updated playlist in a data envelope" do
        patch "/api/v1/playlists/#{playlist.id}", params: { playlist: { sync_enabled: true } }
        expect(response.parsed_body.dig("data", "sync_enabled")).to be(true)
      end

      context "when playlist belongs to another user" do
        let(:other_playlist) { create(:playlist) }

        it "returns 404 not found" do
          patch "/api/v1/playlists/#{other_playlist.id}", params: { playlist: { sync_enabled: true } }
          expect(response).to have_http_status(:not_found)
        end
      end

      context "with invalid parameters" do
        it "ignores non-permitted params" do
          original_name = playlist.name

          patch "/api/v1/playlists/#{playlist.id}", params: { playlist: { name: "Hacked Name", sync_enabled: true } }

          expect(playlist.reload.name).to eq(original_name)
        end
      end
    end
  end
end
