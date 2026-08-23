# frozen_string_literal: true

require "rails_helper"

RSpec.describe Playlists::TrackFilter do
  let(:user) { create(:user) }
  let(:shoegaze) { create(:genre, name: "shoegaze") }
  let(:tagged) { create(:track, :with_genres, title: "Only Shallow", genres: [shoegaze]) }
  let(:untagged) { create(:track, title: "Untagged") }
  let(:playlist) { create(:playlist, :holding, user: user, tracks: [tagged, untagged]) }

  it "returns every track in position order when no genre is given" do
    relation = described_class.new(user, {}, playlist).call

    expect(relation.map { |row| row.track.title }).to eq(["Only Shallow", "Untagged"])
  end

  it "keeps only the tracks carrying the given genre id" do
    relation = described_class.new(user, { genre: shoegaze.id.to_s }, playlist).call

    expect(relation.map { |row| row.track.title }).to eq(["Only Shallow"])
  end

  it "accepts a genre name as well as an id" do
    relation = described_class.new(user, { genre: "Shoegaze" }, playlist).call

    expect(relation.map { |row| row.track.title }).to eq(["Only Shallow"])
  end

  it "matches nothing once the genre is blocked" do
    create(:blocked_genre, user: user, genre: shoegaze)

    relation = described_class.new(user, { genre: shoegaze.id.to_s }, playlist).call

    expect(relation).to be_empty
  end

  it "is empty when the playlist has no current version" do
    relation = described_class.new(user, {}, create(:playlist, user: user)).call

    expect(relation).to be_empty
  end

  # The panel would be lying if these two disagreed.
  it "returns as many tracks as the genre breakdown counts for that genre" do
    create(:track, :with_genres, genres: [shoegaze]) # elsewhere in no playlist
    breakdown = Genres::Filter.new(user, { sort: "track_count" }, tracks: playlist.tracks)
    counts = breakdown.track_counts_for(breakdown.call)

    relation = described_class.new(user, { genre: shoegaze.id.to_s }, playlist).call

    expect(relation.count).to eq(counts[shoegaze.id])
  end
end
