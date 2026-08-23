# frozen_string_literal: true

require "rails_helper"

RSpec.describe Genres::Filter do
  let(:user) { create(:user) }

  describe "track_count sort" do
    it "counts only the user's library tracks" do
      metal = create(:genre, name: "metal")
      rock = create(:genre, name: "rock")
      2.times { create(:track, :in_library, :with_genres, user: user, genres: [metal]) }
      create(:track, :in_library, :with_genres, user: user, genres: [rock])
      create(:track, :in_library, :with_genres, user: create(:user), genres: [rock])

      relation = described_class.new(user, { sort: "track_count", order: "desc" }).call

      expect(relation.map(&:name)).to eq(%w[metal rock])
    end

    it "answers a plain #count, not only count(:all)" do
      create(:track, :in_library, :with_genres, user: user, genres: [create(:genre, name: "metal")])

      relation = described_class.new(user, { sort: "track_count" }).call

      expect(relation.count).to eq(1)
      expect(relation.count(:all)).to eq(1)
    end
  end

  describe "a narrowed track set" do
    let(:metal) { create(:genre, name: "metal") }

    it "lists only the genres those tracks carry" do
      inside = create(:track, :in_library, :with_genres, user: user, genres: [metal])
      create(:track, :in_library, :with_genres, user: user, genre_names: ["rock"])

      relation = described_class.new(user, { sort: "name" }, tracks: Track.where(id: inside)).call

      expect(relation.map(&:name)).to eq(["metal"])
    end

    it "counts only those tracks" do
      inside = create(:track, :in_library, :with_genres, user: user, genres: [metal])
      create(:track, :in_library, :with_genres, user: user, genres: [metal])

      filter = described_class.new(user, { sort: "track_count" }, tracks: Track.where(id: inside))

      expect(filter.track_counts_for(filter.call)).to eq(metal.id => 1)
    end
  end

  describe "#track_counts_for" do
    it "counts the whole library by default" do
      metal = create(:genre, name: "metal")
      2.times { create(:track, :in_library, :with_genres, user: user, genres: [metal]) }

      filter = described_class.new(user, { sort: "track_count" })

      expect(filter.track_counts_for(filter.call)).to eq(metal.id => 2)
    end
  end
end
