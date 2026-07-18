# frozen_string_literal: true

require "rails_helper"

RSpec.describe Album do
  describe ".for_artist" do
    it "returns only the given artist's albums" do
      artist = create(:artist)
      album = create(:album, :with_artists, artists: [artist])
      create(:album, :with_artists)

      expect(described_class.for_artist(artist)).to contain_exactly(album)
    end
  end

  describe ".by_release_year" do
    it "orders ascending with unknown years last" do
      recent = create(:album, release_year: 2020)
      old = create(:album, release_year: 1990)
      unknown = create(:album, release_year: nil)

      expect(described_class.by_release_year.to_a).to eq([old, recent, unknown])
    end
  end
end
