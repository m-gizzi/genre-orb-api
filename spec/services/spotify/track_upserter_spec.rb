# frozen_string_literal: true

require "rails_helper"

RSpec.describe Spotify::TrackUpserter do
  let(:service) { described_class.new }

  # rubocop:disable Metrics/ParameterLists
  def build_spotify_track_item(track_id:, track_name:, artist_id:, artist_name:, album_id:, album_name:)
    # rubocop:enable Metrics/ParameterLists
    {
      "track" => {
        "id" => track_id,
        "name" => track_name,
        "duration_ms" => 180_000,
        "track_number" => 1,
        "explicit" => false,
        "preview_url" => "https://example.com/preview",
        "popularity" => 75,
        "artists" => [
          { "id" => artist_id, "name" => artist_name },
        ],
        "album" => {
          "id" => album_id,
          "name" => album_name,
          "release_date" => "2023-05-15",
          "total_tracks" => 10,
          "images" => [{ "url" => "https://example.com/album.jpg" }],
          "artists" => [{ "id" => artist_id, "name" => artist_name }],
        },
      },
    }
  end

  describe "#call" do
    let(:track_items) do
      [
        build_spotify_track_item(
          track_id: "track_1", track_name: "Song One",
          artist_id: "artist_1", artist_name: "Artist One",
          album_id: "album_1", album_name: "Album One",
        ),
        build_spotify_track_item(
          track_id: "track_2", track_name: "Song Two",
          artist_id: "artist_2", artist_name: "Artist Two",
          album_id: "album_2", album_name: "Album Two",
        ),
      ]
    end

    it "returns hash of tracks indexed by spotify_id" do
      result = service.call(track_items)
      expect(result.keys).to contain_exactly("track_1", "track_2")
      expect(result["track_1"]).to be_a(Track)
    end

    it "creates artists" do
      expect { service.call(track_items) }.to change(Artist, :count).by(2)
    end

    it "creates albums" do
      expect { service.call(track_items) }.to change(Album, :count).by(2)
    end

    it "creates tracks" do
      expect { service.call(track_items) }.to change(Track, :count).by(2)
    end

    it "creates track-artist joins" do
      expect { service.call(track_items) }.to change(TrackArtist, :count).by(2)
    end

    it "creates album-artist joins" do
      expect { service.call(track_items) }.to change(AlbumArtist, :count).by(2)
    end

    context "with empty input" do
      it "returns empty hash" do
        result = service.call([])
        expect(result).to eq({})
      end
    end

    context "when track already exists" do
      before do
        album = create(:album, spotify_id: "album_1")
        create(:track, spotify_id: "track_1", title: "Old Name", album: album)
      end

      it "updates existing track" do
        service.call(track_items)
        track = Track.find_by(spotify_id: "track_1")
        expect(track.title).to eq("Song One")
      end

      it "does not create duplicate" do
        expect { service.call(track_items) }.to change(Track, :count).by(1)
      end
    end

    context "when artist already exists" do
      before do
        create(:artist, spotify_id: "artist_1", name: "Old Artist Name")
      end

      it "updates existing artist" do
        service.call(track_items)
        artist = Artist.find_by(spotify_id: "artist_1")
        expect(artist.name).to eq("Artist One")
      end
    end

    context "with multiple artists per track" do
      let(:track_items) do
        [
          {
            "track" => {
              "id" => "collab_track",
              "name" => "Collaboration",
              "duration_ms" => 200_000,
              "track_number" => 1,
              "explicit" => false,
              "preview_url" => nil,
              "popularity" => 80,
              "artists" => [
                { "id" => "artist_a", "name" => "Artist A" },
                { "id" => "artist_b", "name" => "Artist B" },
              ],
              "album" => {
                "id" => "album_collab",
                "name" => "Collab Album",
                "release_date" => "2024",
                "total_tracks" => 1,
                "images" => [],
                "artists" => [{ "id" => "artist_a", "name" => "Artist A" }],
              },
            },
          },
        ]
      end

      it "creates track-artist joins for all artists" do
        service.call(track_items)
        track = Track.find_by(spotify_id: "collab_track")
        expect(track.artists.pluck(:spotify_id)).to contain_exactly("artist_a", "artist_b")
      end
    end

    context "with nil track data" do
      let(:track_items) do
        [
          { "track" => nil },
          build_spotify_track_item(
            track_id: "valid_track", track_name: "Valid Song",
            artist_id: "artist_1", artist_name: "Artist",
            album_id: "album_1", album_name: "Album",
          ),
        ]
      end

      it "skips nil tracks" do
        result = service.call(track_items)
        expect(result.keys).to eq(["valid_track"])
      end
    end

    context "with year-only release date" do
      let(:track_items) do
        [
          {
            "track" => {
              "id" => "track_year_only",
              "name" => "Year Only",
              "duration_ms" => 100_000,
              "track_number" => 1,
              "explicit" => false,
              "preview_url" => nil,
              "popularity" => 50,
              "artists" => [{ "id" => "a1", "name" => "Artist" }],
              "album" => {
                "id" => "album_year",
                "name" => "Year Album",
                "release_date" => "1999",
                "total_tracks" => 1,
                "images" => [],
                "artists" => [{ "id" => "a1", "name" => "Artist" }],
              },
            },
          },
        ]
      end

      it "extracts year from release date" do
        service.call(track_items)
        album = Album.find_by(spotify_id: "album_year")
        expect(album.release_year).to eq(1999)
      end
    end
  end

  describe "genre propagation from known artists" do
    let(:track_items) do
      [
        build_spotify_track_item(
          track_id: "track_1", track_name: "Song One",
          artist_id: "artist_1", artist_name: "Artist One",
          album_id: "album_1", album_name: "Album One",
        ),
      ]
    end

    context "when the artist already has genre metadata" do
      before do
        create(:artist, spotify_id: "artist_1", metadata: { "genres" => ["death metal", "black metal"] })
      end

      it "copies the artist's genres onto the newly-synced track" do
        service.call(track_items)

        track = Track.find_by(spotify_id: "track_1")
        expect(track.genres.pluck(:name)).to contain_exactly("death metal", "black metal")
      end
    end

    context "when the artist is brand new (no metadata yet)" do
      it "writes no genres (deferred to the artist metadata sync)" do
        expect { service.call(track_items) }.not_to change(TrackGenre, :count)
      end
    end
  end
end
