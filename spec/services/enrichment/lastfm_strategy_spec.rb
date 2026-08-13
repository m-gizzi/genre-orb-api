# frozen_string_literal: true

require "rails_helper"

RSpec.describe Enrichment::LastfmStrategy do
  let(:adapter) { instance_double(LastfmAdapter) }
  let(:strategy) { described_class.new(adapter: adapter) }
  let(:artist) { create(:artist, name: "Gojira") }

  def drip
    Enrichment::Drip.new(strategy: strategy, deadline: 1.minute.from_now, pacer: Enrichment::Pacer.new(0))
  end

  def result(genres: [], name: "Gojira", url: "https://last.fm/music/Gojira")
    LastfmAdapter::Result.new(genres: genres, name: name, url: url)
  end

  it "fetches without a match phase, since getTopTags identifies and answers at once" do
    create(:artist_metadata_source, :lastfm, artist: artist)
    allow(adapter).to receive(:artist_top_tags).and_return(result)

    expect(drip.call).to have_attributes(fetched: 1, matched: 0)
  end

  it "looks the artist up by name when MusicBrainz has not matched them" do
    create(:artist_metadata_source, :lastfm, artist: artist)
    allow(adapter).to receive(:artist_top_tags).and_return(result)

    drip.call

    expect(adapter).to have_received(:artist_top_tags).with(name: "Gojira", mbid: nil)
  end

  # The whole reason MusicBrainz runs first: its exact Spotify link makes Last.fm's
  # lookup exact too, instead of a name match.
  it "borrows the mbid when the artist's MusicBrainz row is matched" do
    create(:artist_metadata_source, :lastfm, artist: artist)
    create(:artist_metadata_source, :matched, artist: artist, source: :musicbrainz, external_id: "mb-1")
    allow(adapter).to receive(:artist_top_tags).and_return(result)

    drip.call

    expect(adapter).to have_received(:artist_top_tags).with(name: "Gojira", mbid: "mb-1")
  end

  it "ignores an unmatched MusicBrainz row rather than passing a stale mbid" do
    create(:artist_metadata_source, :lastfm, artist: artist)
    create(:artist_metadata_source, :unmatched, artist: artist, source: :musicbrainz)
    allow(adapter).to receive(:artist_top_tags).and_return(result)

    drip.call

    expect(adapter).to have_received(:artist_top_tags).with(name: "Gojira", mbid: nil)
  end

  it "loads every row's mbid in one query rather than one per row" do
    create_list(:artist, 3).each do |other|
      create(:artist_metadata_source, :lastfm, artist: other)
      create(:artist_metadata_source, :matched, artist: other, source: :musicbrainz)
    end
    allow(adapter).to receive(:artist_top_tags).and_return(result)

    # The projection `prepare` plucks, which nothing else in the tick selects.
    expect(queries_during { drip.call }.grep(/"artist_metadata_sources"\."external_id" FROM/).size).to eq(1)
  end

  it "records the canonical name and url Last.fm answered with" do
    create(:artist_metadata_source, :lastfm, artist: artist)
    allow(adapter).to receive(:artist_top_tags)
      .and_return(result(name: "Gojira", url: "https://last.fm/music/Gojira"))

    drip.call

    expect(artist.metadata_sources.sole)
      .to have_attributes(state: "matched", external_id: "Gojira", external_url: "https://last.fm/music/Gojira")
  end

  it "writes tags as lastfm-sourced genres carrying their popularity as confidence" do
    create(:artist_metadata_source, :lastfm, artist: artist)
    create(:track, :with_artists, artists: [artist])
    allow(adapter).to receive(:artist_top_tags)
      .and_return(result(genres: [{ name: "Death Metal", confidence: 0.97 }]))

    drip.call

    expect(ArtistGenre.sole).to have_attributes(source: "lastfm", confidence: 0.97)
    expect(TrackGenre.sole).to have_attributes(source: "lastfm", confidence: 0.97)
  end

  it "marks an artist Last.fm does not know as unmatched" do
    create(:artist_metadata_source, :lastfm, artist: artist)
    allow(adapter).to receive(:artist_top_tags).and_raise(Lastfm::NotFoundError)

    expect(drip.call).to have_attributes(unmatched: 1, fetched: 0)
    expect(artist.metadata_sources.sole.state).to eq("unmatched")
  end

  it "stops the tick on a Last.fm rate limit without penalising the row" do
    row = create(:artist_metadata_source, :lastfm, artist: artist)
    allow(adapter).to receive(:artist_top_tags).and_raise(Lastfm::RateLimitError)

    expect(drip.call.aborted).to be(true)
    expect(row.reload.failure_count).to eq(0)
  end
end
