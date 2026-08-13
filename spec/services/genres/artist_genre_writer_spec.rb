# frozen_string_literal: true

require "rails_helper"

RSpec.describe Spotify::ArtistGenrePropagator do
  let(:artist) { create(:artist) }

  it "creates missing genres and links them to the artist" do
    described_class.new.call([{ artist_id: artist.id, genre_name: "Death Metal" }])

    expect(artist.reload.genres.map(&:name)).to eq(["death metal"])
  end

  it "normalizes and de-duplicates genre names" do
    described_class.new.call(
      [
        { artist_id: artist.id, genre_name: "Death  Metal" },
        { artist_id: artist.id, genre_name: "death metal" },
      ],
    )

    expect(artist.reload.genres.count).to eq(1)
  end

  it "reuses an existing genre rather than duplicating it" do
    metal = create(:genre, name: "metal")

    described_class.new.call([{ artist_id: artist.id, genre_name: "metal" }])

    expect(artist.reload.genres).to contain_exactly(metal)
    expect(Genre.where(name: "metal").count).to eq(1)
  end

  it "is idempotent across repeated propagation" do
    2.times { described_class.new.call([{ artist_id: artist.id, genre_name: "metal" }]) }

    expect(ArtistGenre.where(artist: artist).count).to eq(1)
  end

  it "skips blank genre names" do
    described_class.new.call([{ artist_id: artist.id, genre_name: "  " }])

    expect(artist.reload.genres).to be_empty
  end
end
