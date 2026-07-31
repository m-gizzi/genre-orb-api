# frozen_string_literal: true

require "rails_helper"

RSpec.describe Artist do
  describe "#genres" do
    it "returns the genres assigned to the artist" do
      rock = create(:genre, name: "rock")
      metal = create(:genre, name: "metal")
      artist = create(:artist, :with_genres, genres: [rock, metal])

      expect(artist.genres).to contain_exactly(rock, metal)
    end

    it "excludes genres that only reached the artist's tracks through a collaborator" do
      metal = create(:genre, name: "metal")
      new_age = create(:genre, name: "new age")
      slayer = create(:artist, :with_genres, genres: [metal])
      enya = create(:artist, :with_genres, genres: [new_age])
      collaboration = create(:track, :with_artists, artists: [slayer, enya])
      create(:track_genre, track: collaboration, genre: new_age)

      expect(slayer.genres).to contain_exactly(metal)
    end

    it "ignores genres that exist only in unpropagated Spotify metadata" do
      artist = create(:artist, :with_genre_metadata, metadata_genre_names: ["rock"])

      expect(artist.genres).to be_empty
    end
  end

  describe ".synced" do
    it "returns only artists whose metadata has been fetched" do
      synced = create(:artist, metadata_fetched_at: 1.day.ago)
      create(:artist, metadata_fetched_at: nil)

      expect(described_class.synced).to contain_exactly(synced)
    end
  end
end
