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

      it "returns only user's playlists" do
        my_playlist = create(:playlist, user: user, available_on_spotify: true)
        create(:playlist, available_on_spotify: true)

        get "/api/v1/playlists"
        ids = response.parsed_body.pluck("id")

        expect(ids).to contain_exactly(my_playlist.id)
      end

      it "returns only available playlists" do
        available = create(:playlist, user: user, available_on_spotify: true)
        create(:playlist, user: user, available_on_spotify: false)

        get "/api/v1/playlists"
        ids = response.parsed_body.pluck("id")

        expect(ids).to contain_exactly(available.id)
      end

      it "orders playlists by name" do
        create(:playlist, user: user, name: "Zebra", available_on_spotify: true)
        create(:playlist, user: user, name: "Alpha", available_on_spotify: true)
        create(:playlist, user: user, name: "Middle", available_on_spotify: true)

        get "/api/v1/playlists"
        names = response.parsed_body.pluck("name")

        expect(names).to eq(%w[Alpha Middle Zebra])
      end

      it "returns playlist attributes" do
        playlist = create(:playlist, :with_spotify, :sync_enabled, user: user, available_on_spotify: true)

        get "/api/v1/playlists"
        body = response.parsed_body.first

        expect(body["id"]).to eq(playlist.id)
        expect(body["name"]).to eq(playlist.name)
        expect(body["spotify_id"]).to eq(playlist.spotify_id)
        expect(body["sync_enabled"]).to be(true)
        expect(body["available_on_spotify"]).to be(true)
      end

      it "returns track_count from current version" do
        create(:playlist, :with_tracks, tracks_count: 5, user: user, available_on_spotify: true)

        get "/api/v1/playlists"
        expect(response.parsed_body.first["track_count"]).to eq(5)
      end

      it "returns is_liked_songs attribute" do
        create(:liked_songs_playlist, user: user)

        get "/api/v1/playlists"
        expect(response.parsed_body.first["is_liked_songs"]).to be(true)
      end
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

      it "returns updated playlist" do
        patch "/api/v1/playlists/#{playlist.id}", params: { playlist: { sync_enabled: true } }
        expect(response.parsed_body["sync_enabled"]).to be(true)
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

          patch "/api/v1/playlists/#{playlist.id}", params: { playlist: { name: "Hacked Name" } }

          expect(playlist.reload.name).to eq(original_name)
        end
      end
    end
  end
end
