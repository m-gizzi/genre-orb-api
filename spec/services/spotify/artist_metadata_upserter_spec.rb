# frozen_string_literal: true

require "rails_helper"

RSpec.describe Spotify::ArtistMetadataUpserter do
  def spotify_response(artists)
    { "artists" => artists }
  end

  def sp_artist(id:, name: "Artist", genres: [], **extra)
    {
      "id" => id,
      "name" => name,
      "genres" => genres,
      "followers" => { "total" => extra.fetch(:followers, 1000) },
      "popularity" => extra.fetch(:popularity, 50),
      "images" => extra[:image] ? [{ "url" => extra[:image] }] : [],
    }
  end

  describe "#call" do
    let(:artist) { create(:artist, spotify_id: "artist_1", metadata: {}) }
    let(:track) { create(:track) }

    before { create(:track_artist, track: track, artist: artist) }

    it "stores fetched metadata on the artist" do
      described_class.new(
        spotify_response([sp_artist(id: "artist_1", name: "Real Name", genres: ["rock"],
                                    followers: 42, popularity: 88, image: "https://img",)]),
      ).call

      artist.reload
      expect(artist).to have_attributes(name: "Real Name", image_url: "https://img")
      expect(artist.metadata).to include("genres" => ["rock"], "followers" => 42, "popularity" => 88)
      expect(artist.metadata_fetched_at).to be_present
    end

    it "propagates the artist's genres to its tracks" do
      described_class.new(
        spotify_response([sp_artist(id: "artist_1", genres: ["death metal", "black metal"])]),
      ).call

      expect(track.reload.genres.pluck(:name)).to contain_exactly("death metal", "black metal")
    end

    context "when the artist already has stored genres" do
      let(:artist) { create(:artist, spotify_id: "artist_1", metadata: { "genres" => ["doom metal"] }) }

      it "unions new genres with existing rather than replacing them" do
        described_class.new(
          spotify_response([sp_artist(id: "artist_1", genres: ["death metal"])]),
        ).call

        expect(artist.reload.metadata["genres"]).to contain_exactly("doom metal", "death metal")
        expect(track.reload.genres.pluck(:name)).to contain_exactly("doom metal", "death metal")
      end

      it "does not drop existing genres when Spotify returns an empty genre list" do
        described_class.new(spotify_response([sp_artist(id: "artist_1", genres: [])])).call

        expect(artist.reload.metadata["genres"]).to contain_exactly("doom metal")
        expect(track.reload.genres.pluck(:name)).to contain_exactly("doom metal")
      end
    end

    context "with an empty response" do
      it "does nothing" do
        expect { described_class.new(spotify_response([])).call }.not_to change(TrackGenre, :count)
      end
    end
  end
end
