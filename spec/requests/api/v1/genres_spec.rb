# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::Genres" do
  let(:user) { create(:user) }
  let(:playlist) { create(:playlist, user: user) }
  let(:version) do
    create(:playlist_version, playlist: playlist).tap { |v| playlist.update!(current_version: v) }
  end

  def add_track_with_genre(genre)
    track = create(:track)
    create(:track_genre, track: track, genre: genre)
    create(:playlist_version_track, playlist_version: version, track: track)
    track
  end

  describe "GET /api/v1/genres" do
    context "when not authenticated" do
      it "returns 401 unauthorized" do
        get "/api/v1/genres"
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context "when authenticated" do
      before { sign_in user }

      it "returns only genres present in the user's library" do
        metal = create(:genre, name: "metal")
        add_track_with_genre(metal)

        create(:track_genre, track: create(:track), genre: create(:genre, name: "unowned"))

        get "/api/v1/genres"

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body["data"].pluck("name")).to contain_exactly("metal")
        expect(response.parsed_body["meta"]).to include("total" => 1)
      end

      it "filters by search substring" do
        add_track_with_genre(create(:genre, name: "death metal"))
        add_track_with_genre(create(:genre, name: "jazz"))

        get "/api/v1/genres", params: { search: "metal" }

        expect(response.parsed_body["data"].pluck("name")).to contain_exactly("death metal")
      end

      it "sorts by name descending" do
        add_track_with_genre(create(:genre, name: "ambient"))
        add_track_with_genre(create(:genre, name: "zydeco"))

        get "/api/v1/genres", params: { order: "desc" }

        expect(response.parsed_body["data"].pluck("name")).to eq(%w[zydeco ambient])
      end
    end
  end

  describe "GET /api/v1/genres/:id" do
    before { sign_in user }

    it "returns a genre in the user's library" do
      metal = create(:genre, name: "metal")
      add_track_with_genre(metal)

      get "/api/v1/genres/#{metal.id}"

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["data"]).to include("id" => metal.id, "name" => "metal")
    end

    it "returns 404 for a genre outside the user's library" do
      get "/api/v1/genres/#{create(:genre, name: "unowned").id}"

      expect(response).to have_http_status(:not_found)
    end
  end
end
