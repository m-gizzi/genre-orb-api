# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::SmartPlaylists" do
  let(:user) { create(:user) }
  let(:create_url) { "#{Spotify::Client::BASE_URL}/users/spotify_user_1/playlists" }

  def connect_spotify(owner = user)
    create(:service_connection, user: owner, service_user_id: "spotify_user_1",
                                access_token: "test_token", token_expires_at: 1.hour.from_now,)
  end

  describe "GET /api/v1/smart_playlists" do
    context "when not authenticated" do
      it "returns 401 unauthorized" do
        get "/api/v1/smart_playlists"
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context "when authenticated" do
      before { sign_in user }

      it "returns only the user's smart playlists in a data/meta envelope" do
        mine = create(:smart_playlist, user: user)
        create(:smart_playlist)

        get "/api/v1/smart_playlists"

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body["data"].pluck("id")).to contain_exactly(mine.id)
        expect(response.parsed_body["meta"]).to include("total" => 1)
      end

      it "names each smart playlist after its target playlist" do
        create(:smart_playlist, user: user, target_playlist: create(:playlist, :with_spotify, user: user,
                                                                                              name: "Metal Mix",),)

        get "/api/v1/smart_playlists"

        expect(response.parsed_body["data"].first).to include(
          "name" => "Metal Mix",
          "is_ready" => false,
          "is_enabled" => false,
          "source_count" => 1,
        )
      end

      it "sorts by target playlist name" do
        create(:smart_playlist, user: user, target_playlist: create(:playlist, :with_spotify, user: user,
                                                                                              name: "Zebra",),)
        create(:smart_playlist, user: user, target_playlist: create(:playlist, :with_spotify, user: user,
                                                                                              name: "Alpha",),)

        get "/api/v1/smart_playlists", params: { sort: "name", order: "asc" }

        expect(response.parsed_body["data"].pluck("name")).to eq(%w[Alpha Zebra])
      end

      it "filters by target playlist name" do
        create(:smart_playlist, user: user, target_playlist: create(:playlist, :with_spotify, user: user,
                                                                                              name: "Metal Mix",),)
        create(:smart_playlist, user: user, target_playlist: create(:playlist, :with_spotify, user: user,
                                                                                              name: "Jazz",),)

        get "/api/v1/smart_playlists", params: { search: "metal" }

        expect(response.parsed_body["data"].pluck("name")).to eq(["Metal Mix"])
      end
    end
  end

  describe "GET /api/v1/smart_playlists/:id" do
    before { sign_in user }

    it "returns the smart playlist with its source playlists" do
      smart_playlist = create(:smart_playlist, user: user)
      source = smart_playlist.source_playlists.first

      get "/api/v1/smart_playlists/#{smart_playlist.id}"

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["data"]["source_playlists"].pluck("id")).to contain_exactly(source.id)
      expect(response.parsed_body["data"]["target_playlist"]["id"]).to eq(smart_playlist.target_playlist_id)
    end

    it "returns 404 for another user's smart playlist" do
      get "/api/v1/smart_playlists/#{create(:smart_playlist).id}"

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST /api/v1/smart_playlists" do
    let(:source) { create(:playlist, :with_spotify, user: user) }

    context "when not authenticated" do
      it "returns 401 unauthorized" do
        post "/api/v1/smart_playlists", params: { smart_playlist: { target_playlist_id: 1 } }
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context "when converting an existing playlist" do
      let(:target) { create(:playlist, :with_spotify, user: user) }

      before { sign_in user }

      it "creates a draft smart playlist and returns 201" do
        post "/api/v1/smart_playlists",
             params: { smart_playlist: { target_playlist_id: target.id, source_playlist_ids: [source.id] } }

        expect(response).to have_http_status(:created)
        expect(response.parsed_body["data"]).to include("is_enabled" => false, "is_ready" => false)
        expect(response.parsed_body["data"]["source_playlists"].pluck("id")).to contain_exactly(source.id)
        expect(target.reload.sync_enabled).to be(true)
      end

      it "returns 404 for another user's target playlist" do
        post "/api/v1/smart_playlists",
             params: { smart_playlist: { target_playlist_id: create(:playlist).id,
                                         source_playlist_ids: [source.id], } }

        expect(response).to have_http_status(:not_found)
      end

      it "returns 422 when the target already has a smart playlist" do
        create(:smart_playlist, target_playlist: target)

        post "/api/v1/smart_playlists",
             params: { smart_playlist: { target_playlist_id: target.id, source_playlist_ids: [source.id] } }

        expect(response).to have_http_status(:unprocessable_content)
      end

      it "returns 422 when no sources are given" do
        post "/api/v1/smart_playlists",
             params: { smart_playlist: { target_playlist_id: target.id, source_playlist_ids: [] } }

        expect(response).to have_http_status(:unprocessable_content)
      end

      it "returns 422 when no target is given" do
        post "/api/v1/smart_playlists", params: { smart_playlist: { source_playlist_ids: [source.id] } }

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.parsed_body["errors"].first["message"]).to eq("A target playlist is required")
      end
    end

    context "when creating a new playlist and smart playlist together" do
      before do
        connect_spotify
        sign_in user
      end

      let(:payload) do
        {
          smart_playlist: {
            target_playlist_attributes: { name: "Metal Mix", description: "Heavy", is_public: false },
            source_playlist_ids: [source.id],
          },
        }
      end

      it "creates the playlist on Spotify and returns 201" do
        stub_request(:post, create_url)
          .to_return(status: 201, body: { "id" => "spotify_new_1" }.to_json,
                     headers: { "Content-Type" => "application/json" },)

        post "/api/v1/smart_playlists", params: payload

        expect(response).to have_http_status(:created)
        expect(response.parsed_body.dig("data", "target_playlist", "spotify_id")).to eq("spotify_new_1")
        expect(response.parsed_body.dig("data", "name")).to eq("Metal Mix")
      end

      it "returns 502 and creates nothing when Spotify fails" do
        stub_request(:post, create_url).to_return(status: 500, body: "")

        post "/api/v1/smart_playlists", params: payload

        expect(response).to have_http_status(:bad_gateway)
        expect(SmartPlaylist.count).to eq(0)
        expect(Playlist.where(name: "Metal Mix")).to be_empty
      end
    end
  end

  describe "PATCH /api/v1/smart_playlists/:id" do
    let(:smart_playlist) { create(:smart_playlist, user: user) }

    before { sign_in user }

    it "updates the rules" do
      rules = { "match" => "all", "rules" => [{ "field" => "genre", "operator" => "equals", "value" => "metal" }] }

      patch "/api/v1/smart_playlists/#{smart_playlist.id}", params: { smart_playlist: { rules: rules } }

      expect(response).to have_http_status(:ok)
      expect(smart_playlist.reload.rules).to eq(rules)
      expect(response.parsed_body.dig("data", "is_ready")).to be(true)
    end

    it "replaces the source playlists" do
      replacement = create(:playlist, :with_spotify, user: user)

      patch "/api/v1/smart_playlists/#{smart_playlist.id}",
            params: { smart_playlist: { source_playlist_ids: [replacement.id] } }

      expect(response).to have_http_status(:ok)
      expect(smart_playlist.reload.source_playlists).to contain_exactly(replacement)
    end

    it "returns 422 when enabling a smart playlist that has no rules" do
      patch "/api/v1/smart_playlists/#{smart_playlist.id}", params: { smart_playlist: { is_enabled: true } }

      expect(response).to have_http_status(:unprocessable_content)
      expect(smart_playlist.reload.is_enabled).to be(false)
    end

    it "enables a smart playlist that has rules" do
      smart_playlist = create(:smart_playlist, :with_rules, user: user)

      patch "/api/v1/smart_playlists/#{smart_playlist.id}", params: { smart_playlist: { is_enabled: true } }

      expect(response).to have_http_status(:ok)
      expect(smart_playlist.reload.is_enabled).to be(true)
    end

    it "returns 422 when clearing every source" do
      patch "/api/v1/smart_playlists/#{smart_playlist.id}", params: { smart_playlist: { source_playlist_ids: [] } }

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "ignores source ids belonging to another user" do
      patch "/api/v1/smart_playlists/#{smart_playlist.id}",
            params: { smart_playlist: { source_playlist_ids: [create(:playlist).id] } }

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "returns 404 for another user's smart playlist" do
      patch "/api/v1/smart_playlists/#{create(:smart_playlist).id}",
            params: { smart_playlist: { is_enabled: false } }

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "DELETE /api/v1/smart_playlists/:id" do
    before { sign_in user }

    it "removes the smart playlist but keeps the target playlist" do
      smart_playlist = create(:smart_playlist, user: user)
      target = smart_playlist.target_playlist

      delete "/api/v1/smart_playlists/#{smart_playlist.id}"

      expect(response).to have_http_status(:no_content)
      expect(SmartPlaylist.exists?(smart_playlist.id)).to be(false)
      expect(target.reload).to be_persisted
    end

    it "frees the target playlist's sync toggle" do
      smart_playlist = create(:smart_playlist, user: user)
      target = smart_playlist.target_playlist

      delete "/api/v1/smart_playlists/#{smart_playlist.id}"

      expect(target.reload.update(sync_enabled: false)).to be(true)
    end

    it "returns 404 for another user's smart playlist" do
      delete "/api/v1/smart_playlists/#{create(:smart_playlist).id}"

      expect(response).to have_http_status(:not_found)
    end
  end
end
