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

      it "sorts by last_synced_at ascending (nulls first)" do
        recent = create(:playlist, user: user, name: "Recent", available_on_spotify: true,
                                   last_synced_at: 1.hour.ago,)
        old = create(:playlist, user: user, name: "Old", available_on_spotify: true,
                                last_synced_at: 3.days.ago,)
        never = create(:playlist, user: user, name: "Never", available_on_spotify: true,
                                  last_synced_at: nil,)

        get "/api/v1/playlists", params: { sort: "last_synced_at", order: "asc" }

        expect(response.parsed_body["data"].pluck("id")).to eq([never.id, old.id, recent.id])
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

      it "filters by name search" do
        rock = create(:playlist, user: user, name: "Rock Anthems", available_on_spotify: true)
        create(:playlist, user: user, name: "Jazz Standards", available_on_spotify: true)

        get "/api/v1/playlists", params: { search: "rock" }

        expect(response.parsed_body["data"].pluck("id")).to contain_exactly(rock.id)
      end

      it "filters by sync_enabled" do
        synced = create(:playlist, :sync_enabled, user: user, available_on_spotify: true)
        create(:playlist, user: user, available_on_spotify: true)

        get "/api/v1/playlists", params: { sync_enabled: true }

        expect(response.parsed_body["data"].pluck("id")).to contain_exactly(synced.id)
        expect(response.parsed_body["meta"]["total"]).to eq(1)
      end

      it "returns every playlist when sync_enabled is blank" do
        create(:playlist, :sync_enabled, user: user, available_on_spotify: true)
        create(:playlist, user: user, available_on_spotify: true)

        get "/api/v1/playlists", params: { sync_enabled: "" }

        expect(response.parsed_body["meta"]["total"]).to eq(2)
      end

      it "excludes Liked Songs from the index" do
        regular = create(:playlist, user: user, name: "Mix", available_on_spotify: true)
        create(:liked_songs_playlist, user: user)

        get "/api/v1/playlists"

        expect(response.parsed_body["data"].pluck("id")).to contain_exactly(regular.id)
      end
    end
  end

  describe "GET /api/v1/playlists/liked" do
    before { sign_in user }

    it "returns the user's Liked Songs playlist" do
      liked = create(:liked_songs_playlist, user: user)

      get "/api/v1/playlists/liked"

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["data"]).to include(
        "id" => liked.id,
        "is_liked_songs" => true,
      )
    end

    it "returns null data when the user has no Liked Songs playlist" do
      get "/api/v1/playlists/liked"

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["data"]).to be_nil
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
      version = create(:playlist_version, :current, playlist: playlist)
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
          patch "/api/v1/playlists/#{playlist.id}",
                params: { playlist: { spotify_id: "hacked", sync_enabled: true } }

          expect(playlist.reload.spotify_id).to be_nil
        end

        it "returns 422 for a description over Spotify's limit" do
          patch "/api/v1/playlists/#{playlist.id}", params: { playlist: { description: "x" * 301 } }

          expect(response).to have_http_status(:unprocessable_content)
        end
      end

      context "when the playlist is on Spotify" do
        let(:playlist) { create(:playlist, :with_spotify, user: user, name: "Old Name") }
        let(:update_url) { "#{Spotify::Client::BASE_URL}/playlists/#{playlist.spotify_id}" }

        before do
          create(:service_connection, user: user, service_user_id: "spotify_user_1",
                                      access_token: "test_token", token_expires_at: 1.hour.from_now,)
        end

        it "pushes a renamed playlist to Spotify" do
          stub = stub_request(:put, update_url)
                 .with(body: { name: "New Name" }.to_json)
                 .to_return(status: 200, body: "")

          patch "/api/v1/playlists/#{playlist.id}", params: { playlist: { name: "New Name" } }

          expect(response).to have_http_status(:ok)
          expect(stub).to have_been_requested
          expect(playlist.reload.name).to eq("New Name")
        end

        it "returns 502 and keeps the old values when Spotify fails" do
          stub_request(:put, update_url).to_return(status: 500, body: "")

          patch "/api/v1/playlists/#{playlist.id}", params: { playlist: { name: "New Name" } }

          expect(response).to have_http_status(:bad_gateway)
          expect(response.parsed_body["errors"].first["code"]).to eq("spotify_unavailable")
          expect(playlist.reload.name).to eq("Old Name")
        end

        it "returns 429 with Retry-After when Spotify rate limits the write" do
          stub_request(:put, update_url).to_return(status: 429, headers: { "Retry-After" => "12" })

          patch "/api/v1/playlists/#{playlist.id}", params: { playlist: { name: "New Name" } }

          expect(response).to have_http_status(:too_many_requests)
          expect(response.headers["Retry-After"]).to eq("12")
          expect(playlist.reload.name).to eq("Old Name")
        end
      end

      context "when the playlist is Liked Songs" do
        let(:playlist) { create(:liked_songs_playlist, user: user) }

        it "returns 422 for a rename" do
          patch "/api/v1/playlists/#{playlist.id}", params: { playlist: { name: "My Favourites" } }

          expect(response).to have_http_status(:unprocessable_content)
          expect(playlist.reload.name).to eq("Liked Songs")
        end

        it "returns 422 for a description" do
          patch "/api/v1/playlists/#{playlist.id}", params: { playlist: { description: "Mine" } }

          expect(response).to have_http_status(:unprocessable_content)
          expect(playlist.reload.description).to be_nil
        end

        it "still allows toggling sync" do
          patch "/api/v1/playlists/#{playlist.id}", params: { playlist: { sync_enabled: true } }

          expect(response).to have_http_status(:ok)
          expect(playlist.reload.sync_enabled).to be(true)
        end
      end

      context "when the playlist is a smart playlist target" do
        let(:playlist) { create(:smart_playlist).target_playlist }
        let(:user) { playlist.user }

        it "returns 422 when disabling sync" do
          patch "/api/v1/playlists/#{playlist.id}", params: { playlist: { sync_enabled: false } }

          expect(response).to have_http_status(:unprocessable_content)
          expect(playlist.reload.sync_enabled).to be(true)
        end
      end
    end
  end

  describe "POST /api/v1/playlists" do
    let(:create_url) { "#{Spotify::Client::BASE_URL}/users/spotify_user_1/playlists" }
    let(:payload) { { playlist: { name: "Metal Mix", description: "Heavy" } } }

    context "when not authenticated" do
      it "returns 401 unauthorized" do
        post "/api/v1/playlists", params: payload
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context "when authenticated without Spotify" do
      before { sign_in user }

      it "returns 422" do
        post "/api/v1/playlists", params: payload

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.parsed_body["errors"].first["code"]).to eq("spotify_not_connected")
      end
    end

    context "when authenticated with Spotify" do
      before do
        create(:service_connection, user: user, service_user_id: "spotify_user_1",
                                    access_token: "test_token", token_expires_at: 1.hour.from_now,)
        sign_in user
      end

      it "creates the playlist on Spotify and returns 201" do
        stub_request(:post, create_url)
          .to_return(status: 201, body: { "id" => "spotify_new_1" }.to_json,
                     headers: { "Content-Type" => "application/json" },)

        post "/api/v1/playlists", params: payload

        expect(response).to have_http_status(:created)
        expect(response.parsed_body.dig("data", "spotify_id")).to eq("spotify_new_1")
        expect(response.parsed_body.dig("data", "description")).to eq("Heavy")
      end

      it "returns 502 and creates nothing when Spotify fails" do
        stub_request(:post, create_url).to_return(status: 500, body: "")

        post "/api/v1/playlists", params: payload

        expect(response).to have_http_status(:bad_gateway)
        expect(user.playlists.count).to eq(0)
      end

      it "returns 422 for a blank name without calling Spotify" do
        stub = stub_request(:post, create_url)

        post "/api/v1/playlists", params: { playlist: { name: "" } }

        expect(response).to have_http_status(:unprocessable_content)
        expect(stub).not_to have_been_requested
      end
    end
  end
end
