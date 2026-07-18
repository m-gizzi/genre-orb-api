# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::Tracks" do
  let(:user) { create(:user) }
  let(:playlist) { create(:playlist, user: user) }
  let(:version) { create(:playlist_version, :current, playlist: playlist) }

  describe "GET /api/v1/tracks" do
    context "when not authenticated" do
      it "returns 401 unauthorized with the error envelope" do
        get "/api/v1/tracks"

        expect(response).to have_http_status(:unauthorized)
        expect(response.parsed_body["errors"].first["code"]).to eq("unauthenticated")
      end
    end

    context "when authenticated" do
      before { sign_in user }

      it "returns only the current user's library tracks in a data/meta envelope" do
        mine = create(:track, :in_library, current_version: version, title: "Mine")

        old_version = create(:playlist_version, playlist: playlist)
        create(:playlist_version_track, playlist_version: old_version, track: create(:track, title: "Old"))

        create(:track, :in_library, user: create(:user), title: "Theirs")

        get "/api/v1/tracks"

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body["data"].pluck("id")).to contain_exactly(mine.id)
        expect(response.parsed_body["data"].first).to include("album", "artists", "genres")
      end

      it "reports pagination in meta and honors per_page" do
        3.times { |i| create(:track, :in_library, current_version: version, title: "T#{i}") }

        get "/api/v1/tracks", params: { per_page: 2 }

        expect(response.parsed_body["data"].size).to eq(2)
        expect(response.parsed_body["meta"]).to eq(
          "page" => 1, "per_page" => 2, "total" => 3, "total_pages" => 2,
        )
      end

      it "caps per_page at 100" do
        create(:track, :in_library, current_version: version)

        get "/api/v1/tracks", params: { per_page: 1000 }

        expect(response.parsed_body["meta"]["per_page"]).to eq(100)
      end

      it "treats an out-of-range page as the last page" do
        3.times { |i| create(:track, :in_library, current_version: version, title: "T#{i}") }

        get "/api/v1/tracks", params: { per_page: 2, page: 99 }

        expect(response.parsed_body["meta"]["page"]).to eq(2)
        expect(response.parsed_body["data"].size).to eq(1)
      end

      it "filters by genre" do
        metal = create(:genre, name: "metal")
        loud = create(:track, :in_library, :with_genres, current_version: version, title: "Loud", genres: [metal])
        create(:track, :in_library, :with_genres, current_version: version, title: "Quiet",
                                                  genres: [create(:genre, name: "ambient")],)

        get "/api/v1/tracks", params: { genre: "metal" }

        expect(response.parsed_body["data"].pluck("id")).to contain_exactly(loud.id)
      end

      it "filters by duration range" do
        loud = create(:track, :in_library, current_version: version, duration_ms: 300_000)
        create(:track, :in_library, current_version: version, duration_ms: 100_000)

        get "/api/v1/tracks", params: { duration_min: 200_000 }

        expect(response.parsed_body["data"].pluck("id")).to contain_exactly(loud.id)
      end

      it "filters by explicit flag" do
        create(:track, :in_library, current_version: version, explicit: true)
        clean = create(:track, :in_library, current_version: version, explicit: false)

        get "/api/v1/tracks", params: { explicit: false }

        expect(response.parsed_body["data"].pluck("id")).to contain_exactly(clean.id)
      end

      it "sorts by popularity descending" do
        low = create(:track, :in_library, current_version: version, title: "Low", popularity: 10)
        high = create(:track, :in_library, current_version: version, title: "High", popularity: 90)

        get "/api/v1/tracks", params: { sort: "popularity", order: "desc" }

        expect(response.parsed_body["data"].pluck("id")).to eq([high.id, low.id])
      end

      it "sorts by album release year and still reports an accurate count" do
        newer = create(:track, :in_library, current_version: version, title: "Newer",
                                            album: create(:album, release_year: 2021),)
        older = create(:track, :in_library, current_version: version, title: "Older",
                                            album: create(:album, release_year: 1999),)

        get "/api/v1/tracks", params: { sort: "year", order: "desc" }

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body["data"].pluck("id")).to eq([newer.id, older.id])
        expect(response.parsed_body["meta"]["total"]).to eq(2)
      end
    end
  end

  describe "GET /api/v1/tracks/:id" do
    before { sign_in user }

    it "returns a library track with nested associations" do
      album = create(:album, title: "Reign")
      track = create(:track, :in_library, :with_genres, current_version: version, title: "Angel",
                                                        album: album, genres: [create(:genre, name: "thrash")],)

      get "/api/v1/tracks/#{track.id}"

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["data"]).to include("id" => track.id, "title" => "Angel")
      expect(response.parsed_body["data"]["album"]).to include("title" => "Reign")
      expect(response.parsed_body["data"]["genres"].first).to include("source" => "spotify")
    end

    it "returns 404 for a track outside the user's library" do
      other_track = create(:track)

      get "/api/v1/tracks/#{other_track.id}"

      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body["errors"].first["code"]).to eq("not_found")
    end
  end
end
