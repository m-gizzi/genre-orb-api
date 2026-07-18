# frozen_string_literal: true

require "rails_helper"

RSpec.describe Artist do
  describe "#genres" do
    it "returns the distinct genres of the artist's tracks" do
      artist = create(:artist)
      rock = create(:genre, name: "rock")
      metal = create(:genre, name: "metal")
      track_one = create(:track, :with_artists, artists: [artist])
      track_two = create(:track, :with_artists, artists: [artist])
      create(:track_genre, track: track_one, genre: rock)
      create(:track_genre, track: track_two, genre: rock)
      create(:track_genre, track: track_two, genre: metal)

      expect(artist.genres).to contain_exactly(rock, metal)
    end

    it "ignores metadata genres — only track genres count" do
      artist = create(:artist, metadata: { "genres" => ["rock"] })
      create(:track, :with_artists, artists: [artist])

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
