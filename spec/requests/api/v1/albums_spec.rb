# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::Albums" do
  let(:user) { create(:user) }
  let(:playlist) { create(:playlist, user: user) }
  let(:version) do
    create(:playlist_version, playlist: playlist).tap { |v| playlist.update!(current_version: v) }
  end

  def add_track(track)
    create(:playlist_version_track, playlist_version: version, track: track)
    track
  end

  describe "GET /api/v1/albums" do
    context "when not authenticated" do
      it "returns 401 unauthorized" do
        get "/api/v1/albums"
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context "when authenticated" do
      before { sign_in user }

      it "returns only albums in the user's library, with nested artists and a meta envelope" do
        artist = create(:artist, name: "Slayer")
        album = create(:album, title: "Reign in Blood")
        create(:album_artist, album: album, artist: artist)
        add_track(create(:track, album: album))

        other_album = create(:album, title: "Unowned")
        create(:track, album: other_album)

        get "/api/v1/albums"

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body["data"].pluck("id")).to contain_exactly(album.id)
        expect(response.parsed_body["data"].first["artists"].first).to include("name" => "Slayer")
        expect(response.parsed_body["meta"]).to include("page" => 1, "total" => 1)
      end

      it "filters by title search" do
        reign = create(:album, title: "Reign in Blood")
        add_track(create(:track, album: reign))
        seasons = create(:album, title: "Seasons in the Abyss")
        add_track(create(:track, album: seasons))

        get "/api/v1/albums", params: { search: "reign" }

        expect(response.parsed_body["data"].pluck("id")).to contain_exactly(reign.id)
      end

      it "filters by genre id" do
        metal = create(:genre, name: "metal")
        reign = create(:album, title: "Reign in Blood")
        create(:track_genre, track: add_track(create(:track, album: reign)), genre: metal)
        watermark = create(:album, title: "Watermark")
        create(:track_genre, track: add_track(create(:track, album: watermark)), genre: create(:genre, name: "new age"))

        get "/api/v1/albums", params: { genre: metal.id }

        expect(response.parsed_body["data"].pluck("id")).to contain_exactly(reign.id)
      end

      it "filters by genre name" do
        metal = create(:genre, name: "metal")
        reign = create(:album, title: "Reign in Blood")
        create(:track_genre, track: add_track(create(:track, album: reign)), genre: metal)
        watermark = create(:album, title: "Watermark")
        create(:track_genre, track: add_track(create(:track, album: watermark)), genre: create(:genre, name: "new age"))

        get "/api/v1/albums", params: { genre: "metal" }

        expect(response.parsed_body["data"].pluck("id")).to contain_exactly(reign.id)
      end
    end
  end

  describe "GET /api/v1/albums/:id" do
    before { sign_in user }

    it "returns the album with its library tracks" do
      album = create(:album, title: "Reign in Blood")
      in_library = add_track(create(:track, title: "Angel of Death", album: album, track_number: 1))
      create(:track, title: "Not Owned", album: album, track_number: 2)

      get "/api/v1/albums/#{album.id}"

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["data"]).to include("id" => album.id, "title" => "Reign in Blood")
      expect(response.parsed_body["data"]["tracks"].pluck("id")).to contain_exactly(in_library.id)
    end

    it "returns 404 for an album outside the user's library" do
      get "/api/v1/albums/#{create(:album).id}"

      expect(response).to have_http_status(:not_found)
    end
  end
end
