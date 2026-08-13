# frozen_string_literal: true

require "rails_helper"

RSpec.describe Enrichment::Coverage do
  subject(:coverage) { described_class.new(user).call }

  let(:user) { create(:user) }

  it "reports both enrichment sources and neither Spotify nor user" do
    expect(coverage.keys).to contain_exactly(:musicbrainz, :lastfm)
  end

  it "counts an artist with no row yet as pending" do
    create(:artist, :in_library, user: user)

    expect(coverage[:musicbrainz]).to include(total: 1, pending: 1, matched: 0, fetched: 0)
  end

  it "counts an enrolled but untouched row as pending" do
    artist = create(:artist, :in_library, user: user)
    create(:artist_metadata_source, artist: artist, source: :musicbrainz)

    expect(coverage[:musicbrainz]).to include(total: 1, pending: 1)
  end

  # matched-with-an-identifier and genres-actually-read are different milestones,
  # because the MusicBrainz drip needs a tick for each.
  it "distinguishes matched from fetched" do
    artist = create(:artist, :in_library, user: user)
    create(:artist_metadata_source, :matched, artist: artist, source: :musicbrainz)

    expect(coverage[:musicbrainz]).to include(matched: 1, fetched: 0)
  end

  it "counts a fetched row under both matched and fetched" do
    artist = create(:artist, :in_library, user: user)
    create(:artist_metadata_source, :fetched, artist: artist, source: :musicbrainz)

    expect(coverage[:musicbrainz]).to include(matched: 1, fetched: 1, pending: 0)
  end

  it "counts unmatched and errored rows separately" do
    first = create(:artist, :in_library, user: user)
    second = create(:artist, :in_library, user: user)
    create(:artist_metadata_source, :unmatched, artist: first, source: :musicbrainz)
    create(:artist_metadata_source, :errored, artist: second, source: :musicbrainz)

    expect(coverage[:musicbrainz]).to include(total: 2, unmatched: 1, errored: 1, pending: 0)
  end

  it "keeps the two sources' counts independent" do
    artist = create(:artist, :in_library, user: user)
    create(:artist_metadata_source, :fetched, artist: artist, source: :musicbrainz)

    expect(coverage[:lastfm]).to include(fetched: 0, pending: 1)
  end

  it "ignores artists outside the user's library" do
    create(:artist_metadata_source, :fetched, artist: create(:artist), source: :musicbrainz)

    expect(coverage[:musicbrainz]).to include(total: 0, fetched: 0)
  end

  it "reports zeroes for an empty library" do
    expect(coverage[:musicbrainz]).to eq(total: 0, fetched: 0, matched: 0, unmatched: 0, errored: 0, pending: 0)
  end
end
