# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::Tracks" do
  let(:user) { create(:user) }
  let(:playlist) { create(:playlist, user: user) }
  let(:version) do
    create(:playlist_version, playlist: playlist).tap { |v| playlist.update!(current_version: v) }
  end

  def add_track(track)
    create(:playlist_version_track, playlist_version: version, track: track)
    track
  end

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
        mine = add_track(create(:track, title: "Mine"))

        old_version = create(:playlist_version, playlist: playlist)
        create(:playlist_version_track, playlist_version: old_version, track: create(:track, title: "Old"))

        other_playlist = create(:playlist, user: create(:user))
        other_version = create(:playlist_version, playlist: other_playlist)
        other_playlist.update!(current_version: other_version)
        create(:playlist_version_track, playlist_version: other_version, track: create(:track, title: "Theirs"))

        get "/api/v1/tracks"

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body["data"].pluck("id")).to contain_exactly(mine.id)
        expect(response.parsed_body["data"].first).to include("album", "artists", "genres")
      end

      it "reports pagination in meta and honors per_page" do
        3.times { |i| add_track(create(:track, title: "T#{i}")) }

        get "/api/v1/tracks", params: { per_page: 2 }

        expect(response.parsed_body["data"].size).to eq(2)
        expect(response.parsed_body["meta"]).to eq(
          "page" => 1, "per_page" => 2, "total" => 3, "total_pages" => 2,
        )
      end

      it "caps per_page at 100" do
        add_track(create(:track))

        get "/api/v1/tracks", params: { per_page: 1000 }

        expect(response.parsed_body["meta"]["per_page"]).to eq(100)
      end

      it "treats an out-of-range page as the last page" do
        3.times { |i| add_track(create(:track, title: "T#{i}")) }

        get "/api/v1/tracks", params: { per_page: 2, page: 99 }

        expect(response.parsed_body["meta"]["page"]).to eq(2)
        expect(response.parsed_body["data"].size).to eq(1)
      end

      it "filters by genre" do
        metal = create(:genre, name: "metal")
        loud = add_track(create(:track, title: "Loud"))
        create(:track_genre, track: loud, genre: metal)
        quiet = add_track(create(:track, title: "Quiet"))
        create(:track_genre, track: quiet, genre: create(:genre, name: "ambient"))

        get "/api/v1/tracks", params: { genre: "metal" }

        expect(response.parsed_body["data"].pluck("id")).to contain_exactly(loud.id)
      end

      it "filters by duration range" do
        loud = add_track(create(:track, duration_ms: 300_000))
        add_track(create(:track, duration_ms: 100_000))

        get "/api/v1/tracks", params: { duration_min: 200_000 }

        expect(response.parsed_body["data"].pluck("id")).to contain_exactly(loud.id)
      end

      it "filters by explicit flag" do
        add_track(create(:track, explicit: true))
        clean = add_track(create(:track, explicit: false))

        get "/api/v1/tracks", params: { explicit: false }

        expect(response.parsed_body["data"].pluck("id")).to contain_exactly(clean.id)
      end

      it "sorts by popularity descending" do
        low = add_track(create(:track, title: "Low", popularity: 10))
        high = add_track(create(:track, title: "High", popularity: 90))

        get "/api/v1/tracks", params: { sort: "popularity", order: "desc" }

        expect(response.parsed_body["data"].pluck("id")).to eq([high.id, low.id])
      end
    end
  end

  describe "GET /api/v1/tracks/:id" do
    before { sign_in user }

    it "returns a library track with nested associations" do
      album = create(:album, title: "Reign")
      track = add_track(create(:track, title: "Angel", album: album))
      create(:track_genre, track: track, genre: create(:genre, name: "thrash"))

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
