# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::Genres" do
  let(:user) { create(:user) }
  let(:playlist) { create(:playlist, user: user) }
  let(:version) { create(:playlist_version, :current, playlist: playlist) }

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
        create(:track, :in_library, :with_genres, current_version: version, genres: [metal])

        create(:track_genre, track: create(:track), genre: create(:genre, name: "unowned"))

        get "/api/v1/genres"

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body["data"].pluck("name")).to contain_exactly("metal")
        expect(response.parsed_body["meta"]).to include("total" => 1)
      end

      it "filters by search substring" do
        create(:track, :in_library, :with_genres, current_version: version,
                                                  genres: [create(:genre, name: "death metal")],)
        create(:track, :in_library, :with_genres, current_version: version,
                                                  genres: [create(:genre, name: "jazz")],)

        get "/api/v1/genres", params: { search: "metal" }

        expect(response.parsed_body["data"].pluck("name")).to contain_exactly("death metal")
      end

      it "sorts by name descending" do
        create(:track, :in_library, :with_genres, current_version: version,
                                                  genres: [create(:genre, name: "ambient")],)
        create(:track, :in_library, :with_genres, current_version: version,
                                                  genres: [create(:genre, name: "zydeco")],)

        get "/api/v1/genres", params: { order: "desc" }

        expect(response.parsed_body["data"].pluck("name")).to eq(%w[zydeco ambient])
      end

      it "sorts by the number of associated library tracks" do
        metal = create(:genre, name: "metal")
        rock = create(:genre, name: "rock")
        2.times do
          create(:track, :in_library, :with_genres, current_version: version, genres: [metal])
        end
        create(:track, :in_library, :with_genres, current_version: version, genres: [rock])

        get "/api/v1/genres", params: { sort: "track_count", order: "desc" }

        expect(response.parsed_body["data"].pluck("name")).to eq(%w[metal rock])
        expect(response.parsed_body["meta"]).to include("total" => 2)
      end
    end
  end

  describe "GET /api/v1/genres/:id" do
    before { sign_in user }

    it "returns a genre in the user's library" do
      metal = create(:genre, name: "metal")
      create(:track, :in_library, :with_genres, current_version: version, genres: [metal])

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
