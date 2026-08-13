# frozen_string_literal: true

require "rails_helper"

RSpec.describe Genres::ArtistGenreWriter do
  subject(:writer) { described_class.new(source: :spotify) }

  let(:artist) { create(:artist) }

  it "creates missing genres and links them to the artist" do
    writer.call([{ artist_id: artist.id, genre_name: "Death Metal" }])

    expect(artist.reload.genres.map(&:name)).to eq(["death metal"])
  end

  it "normalizes and de-duplicates genre names" do
    writer.call(
      [
        { artist_id: artist.id, genre_name: "Death  Metal" },
        { artist_id: artist.id, genre_name: "death metal" },
      ],
    )

    expect(artist.reload.genres.count).to eq(1)
  end

  it "reuses an existing genre rather than duplicating it" do
    metal = create(:genre, name: "metal")

    writer.call([{ artist_id: artist.id, genre_name: "metal" }])

    expect(artist.reload.genres).to contain_exactly(metal)
    expect(Genre.where(name: "metal").count).to eq(1)
  end

  it "is idempotent across repeated writes" do
    2.times { writer.call([{ artist_id: artist.id, genre_name: "metal" }]) }

    expect(ArtistGenre.where(artist: artist).count).to eq(1)
  end

  it "skips blank genre names" do
    writer.call([{ artist_id: artist.id, genre_name: "  " }])

    expect(artist.reload.genres).to be_empty
  end

  it "stamps rows with the writer's source" do
    described_class.new(source: :lastfm).call([{ artist_id: artist.id, genre_name: "metal" }])

    expect(ArtistGenre.where(artist: artist).pluck(:source)).to eq(["lastfm"])
  end

  it "defaults confidence to 1.0 when a pair carries none" do
    writer.call([{ artist_id: artist.id, genre_name: "metal" }])

    expect(ArtistGenre.sole.confidence).to eq(1.0)
  end

  it "records the confidence a pair carries" do
    described_class.new(source: :lastfm).call(
      [{ artist_id: artist.id, genre_name: "metal", confidence: 0.42 }],
    )

    expect(ArtistGenre.sole.confidence).to be_within(0.001).of(0.42)
  end

  it "clamps a confidence outside 0..1 into range" do
    described_class.new(source: :lastfm).call(
      [{ artist_id: artist.id, genre_name: "metal", confidence: 7.5 }],
    )

    expect(ArtistGenre.sole.confidence).to eq(1.0)
  end

  it "refreshes the confidence of a row it has already written" do
    lastfm = described_class.new(source: :lastfm)
    lastfm.call([{ artist_id: artist.id, genre_name: "metal", confidence: 0.2 }])
    lastfm.call([{ artist_id: artist.id, genre_name: "metal", confidence: 0.9 }])

    expect(ArtistGenre.sole.confidence).to be_within(0.001).of(0.9)
  end

  it "keeps the strongest attribution when one batch repeats a genre" do
    described_class.new(source: :lastfm).call(
      [
        { artist_id: artist.id, genre_name: "metal", confidence: 0.3 },
        { artist_id: artist.id, genre_name: "Metal", confidence: 0.8 },
      ],
    )

    expect(ArtistGenre.sole.confidence).to be_within(0.001).of(0.8)
  end

  it "leaves another source's row for the same genre alone" do
    metal = create(:genre, name: "metal")
    create(:artist_genre, artist: artist, genre: metal, source: :spotify, confidence: 1.0)

    described_class.new(source: :musicbrainz).call(
      [{ artist_id: artist.id, genre_name: "metal", confidence: 0.5 }],
    )

    expect(ArtistGenre.where(artist: artist, genre: metal).pluck(:source, :confidence))
      .to contain_exactly(["spotify", 1.0], ["musicbrainz", 0.5])
  end
end
