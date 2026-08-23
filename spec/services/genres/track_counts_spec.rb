# frozen_string_literal: true

require "rails_helper"

RSpec.describe Genres::TrackCounts do
  let(:user) { create(:user) }
  let(:scope) { Genres::EffectiveScope.new(user) }
  let(:genre) { create(:genre, name: "shoegaze") }

  describe "#for_genres" do
    it "counts a track once even when several sources claim the same genre" do
      track = create(:track)
      create(:track_genre, track: track, genre: genre)
      create(:track_genre, :from_lastfm, track: track, genre: genre)

      counts = described_class.new(scope, Track.where(id: track)).for_genres([genre])

      expect(counts).to eq(genre.id => 1)
    end

    it "counts only the tracks it was given" do
      inside = create(:track, :with_genres, genres: [genre])
      create(:track, :with_genres, genres: [genre])

      counts = described_class.new(scope, Track.where(id: inside)).for_genres([genre])

      expect(counts).to eq(genre.id => 1)
    end

    it "leaves a genre the tracks do not carry out of the hash" do
      track = create(:track, :with_genres, genres: [genre])
      absent = create(:genre, name: "dream pop")

      counts = described_class.new(scope, Track.where(id: track)).for_genres([genre, absent])

      expect(counts).to eq(genre.id => 1)
    end

    it "drops a blocked genre, because the scope has already removed it" do
      track = create(:track, :with_genres, genres: [genre])
      create(:blocked_genre, user: user, genre: genre)

      counts = described_class.new(scope, Track.where(id: track)).for_genres([genre])

      expect(counts).to be_empty
    end
  end

  describe "#genre_ids" do
    it "selects the genres the track set carries" do
      track = create(:track, :with_genres, genres: [genre])
      create(:track, :with_genres, genre_names: ["new wave"])

      relation = described_class.new(scope, Track.where(id: track)).genre_ids

      expect(Genre.where(id: relation).map(&:name)).to eq(["shoegaze"])
    end
  end
end
