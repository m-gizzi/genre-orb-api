# frozen_string_literal: true

require "rails_helper"

RSpec.describe Enrichment::Drip do
  # A pacer with no interval never sleeps, so specs need no time doubles.
  let(:pacer) { Enrichment::Pacer.new(0) }
  let(:adapter) { instance_double(MusicbrainzAdapter) }
  let(:strategy) { Enrichment::MusicbrainzStrategy.new(adapter: adapter) }

  def drip(deadline: 1.minute.from_now)
    described_class.new(strategy: strategy, deadline: deadline, pacer: pacer)
  end

  describe "backfill" do
    it "creates a pending row for an artist that has none for this source" do
      artist = create(:artist)
      allow(adapter).to receive(:artists_by_spotify_url).and_return({})

      drip.call

      expect(artist.metadata_sources.sole).to have_attributes(source: "musicbrainz", state: "unmatched")
    end

    it "does not create a row for a source that already has one" do
      create(:artist_metadata_source, :fetched, artist: create(:artist), source: :musicbrainz)

      expect { drip.call }.not_to change(ArtistMetadataSource, :count)
    end

    it "leaves another source's rows alone" do
      artist = create(:artist)
      create(:artist_metadata_source, :lastfm, :fetched, artist: artist)
      allow(adapter).to receive(:artists_by_spotify_url).and_return({})

      drip.call

      expect(artist.metadata_sources.pluck(:source)).to contain_exactly("lastfm", "musicbrainz")
    end

    # The anti-join cannot stop at its LIMIT until it has walked every artist, so once
    # the source is caught up it must not run at all — this fires every minute forever.
    it "does not scan for missing artists once the source is fully enrolled" do
      create(:artist_metadata_source, :fetched, artist: create(:artist), source: :musicbrainz)

      queries = queries_during { drip.call }

      expect(queries.grep(/NOT IN \(SELECT/)).to be_empty
    end

    it "still scans while artists remain unenrolled" do
      create(:artist)
      allow(adapter).to receive(:artists_by_spotify_url).and_return({})

      queries = queries_during { drip.call }

      expect(queries.grep(/NOT IN \(SELECT/)).not_to be_empty
    end
  end

  describe "the match phase" do
    let(:artist) { create(:artist, spotify_id: "sp_gojira") }

    before { create(:artist_metadata_source, artist: artist, source: :musicbrainz) }

    it "stores the mbid MusicBrainz returns" do
      allow(adapter).to receive(:artists_by_spotify_url).with(["sp_gojira"]).and_return("sp_gojira" => "mb-1")

      drip.call

      expect(artist.metadata_sources.sole)
        .to have_attributes(state: "matched", external_id: "mb-1", retry_after: nil)
    end

    it "leaves a matched row due immediately so the next tick fetches its genres" do
      allow(adapter).to receive(:artists_by_spotify_url).and_return("sp_gojira" => "mb-1")

      drip.call

      expect(ArtistMetadataSource.where(source: :musicbrainz).due).to include(artist.metadata_sources.sole)
    end

    it "marks an artist MusicBrainz does not link as unmatched with a long retry" do
      allow(adapter).to receive(:artists_by_spotify_url).and_return({})

      drip.call

      row = artist.metadata_sources.sole
      expect(row.state).to eq("unmatched")
      expect(row.retry_after).to be_within(1.minute).of(ArtistMetadataSource::UNMATCHED_RETRY.from_now)
    end

    it "batches the lookup at the adapter's resource limit" do
      create_list(:artist, MusicbrainzAdapter::RESOURCE_BATCH_LIMIT)
      allow(adapter).to receive(:artists_by_spotify_url).and_return({})

      drip.call

      expect(adapter).to have_received(:artists_by_spotify_url).twice
    end

    it "reports what it did" do
      other = create(:artist, spotify_id: "sp_other")
      create(:artist_metadata_source, artist: other, source: :musicbrainz)
      allow(adapter).to receive(:artists_by_spotify_url).and_return("sp_gojira" => "mb-1")

      expect(drip.call).to have_attributes(matched: 1, unmatched: 1, fetched: 0, failed: 0, aborted: false)
    end
  end

  describe "the fetch phase" do
    let(:artist) { create(:artist) }
    let!(:row) { create(:artist_metadata_source, :matched, artist: artist, external_id: "mb-1") }

    before do
      create(:track, :with_artists, artists: [artist])
      allow(adapter).to receive(:artists_by_spotify_url).and_return({})
    end

    it "writes the artist's genres with the source's own attribution" do
      allow(adapter).to receive(:artist_genres).with("mb-1")
                                               .and_return([{ name: "Death Metal", confidence: 0.7 }])

      drip.call

      expect(ArtistGenre.sole).to have_attributes(source: "musicbrainz", confidence: 0.7)
      expect(Genre.sole.name).to eq("death metal")
    end

    it "derives the genre onto the artist's tracks" do
      allow(adapter).to receive(:artist_genres).and_return([{ name: "death metal", confidence: 0.7 }])

      drip.call

      expect(TrackGenre.sole).to have_attributes(source: "musicbrainz", confidence: 0.7)
    end

    it "stamps fetched_at and schedules the refresh" do
      allow(adapter).to receive(:artist_genres).and_return([])

      drip.call

      row.reload
      expect(row.fetched_at).to be_present
      expect(row.retry_after).to be_within(1.minute).of(ArtistMetadataSource::REFRESH_TTL.from_now)
    end

    it "writes no genres for an artist MusicBrainz knows but has not tagged" do
      allow(adapter).to receive(:artist_genres).and_return([])

      expect { drip.call }.not_to change(ArtistGenre, :count)
    end

    it "counts an untagged artist as fetched rather than unmatched" do
      allow(adapter).to receive(:artist_genres).and_return([])

      expect(drip.call).to have_attributes(fetched: 1, unmatched: 0)
    end

    it "drops a dead mbid so the next pass re-matches it" do
      allow(adapter).to receive(:artist_genres).and_raise(Musicbrainz::NotFoundError)

      drip.call

      expect(row.reload).to have_attributes(state: "unmatched", external_id: nil)
    end
  end

  describe "failure handling" do
    let(:artist) { create(:artist) }
    let!(:row) { create(:artist_metadata_source, :matched, artist: artist) }

    before { allow(adapter).to receive(:artists_by_spotify_url).and_return({}) }

    it "records an API error against the row with a backoff" do
      allow(adapter).to receive(:artist_genres).and_raise(Musicbrainz::ApiError, "boom")

      expect(drip.call.failed).to eq(1)
      expect(row.reload).to have_attributes(state: "errored", failure_count: 1, last_error: "boom")
      expect(row.retry_after).to be_within(1.minute).of(ArtistMetadataSource::ERROR_BACKOFF_BASE.from_now)
    end

    it "grows the backoff with repeated failures" do
      row.update!(failure_count: 3)
      allow(adapter).to receive(:artist_genres).and_raise(Musicbrainz::ApiError, "boom")

      drip.call

      expect(row.reload.retry_after).to be_within(1.minute).of((ArtistMetadataSource::ERROR_BACKOFF_BASE * 8).from_now)
    end

    it "caps the backoff" do
      row.update!(failure_count: 40)
      allow(adapter).to receive(:artist_genres).and_raise(Musicbrainz::ApiError, "boom")

      drip.call

      expect(row.reload.retry_after).to be_within(1.minute).of(ArtistMetadataSource::ERROR_BACKOFF_CAP.from_now)
    end

    it "treats a connection failure as a row failure rather than crashing the tick" do
      allow(adapter).to receive(:artist_genres).and_raise(Faraday::ConnectionFailed, "down")

      expect { drip.call }.not_to raise_error
      expect(row.reload.state).to eq("errored")
    end

    it "keeps going after one row fails" do
      second = create(:artist_metadata_source, :matched, artist: create(:artist))
      allow(adapter).to receive(:artist_genres).and_raise(Musicbrainz::ApiError, "boom")

      drip.call

      expect([row, second].map { |r| r.reload.state }).to eq(%w[errored errored])
    end
  end

  describe "throttling" do
    let!(:row) { create(:artist_metadata_source, :matched, artist: create(:artist)) }

    before { allow(adapter).to receive(:artists_by_spotify_url).and_return({}) }

    it "stops the tick instead of penalising the row" do
      allow(adapter).to receive(:artist_genres).and_raise(Musicbrainz::RateLimitError)

      expect(drip.call.aborted).to be(true)
      expect(row.reload).to have_attributes(state: "matched", failure_count: 0)
    end

    it "leaves the row due so the next tick retries it" do
      allow(adapter).to receive(:artist_genres).and_raise(Musicbrainz::RateLimitError)

      drip.call

      expect(ArtistMetadataSource.where(source: :musicbrainz).due).to include(row)
    end
  end

  describe "the tick budget" do
    before { allow(adapter).to receive(:artists_by_spotify_url).and_return({}) }

    it "stops fetching once the deadline passes" do
      create_list(:artist, 3).each { |artist| create(:artist_metadata_source, :matched, artist: artist) }
      allow(adapter).to receive(:artist_genres).and_return([])

      drip(deadline: 1.second.ago).call

      expect(adapter).not_to have_received(:artist_genres)
    end

    it "leaves un-processed rows due for the next tick" do
      create_list(:artist, 3).each { |artist| create(:artist_metadata_source, :matched, artist: artist) }
      allow(adapter).to receive(:artist_genres).and_return([])

      drip(deadline: 1.second.ago).call

      expect(ArtistMetadataSource.where(source: :musicbrainz).due.count).to eq(3)
    end
  end

  describe "row selection" do
    before { allow(adapter).to receive(:artists_by_spotify_url).and_return({}) }

    it "skips a row whose retry_after has not arrived" do
      create(:artist_metadata_source, :fetched, artist: create(:artist))
      allow(adapter).to receive(:artist_genres).and_return([])

      drip.call

      expect(adapter).not_to have_received(:artist_genres)
    end

    it "picks a row up again once retry_after has passed" do
      row = create(:artist_metadata_source, :fetched, artist: create(:artist))
      row.update!(retry_after: 1.day.ago)
      allow(adapter).to receive(:artist_genres).and_return([])

      drip.call

      expect(adapter).to have_received(:artist_genres).once
    end

    it "ignores another source's due rows" do
      create(:artist_metadata_source, :lastfm, :matched, artist: create(:artist))
      allow(adapter).to receive(:artist_genres).and_return([])

      drip.call

      expect(adapter).not_to have_received(:artist_genres)
    end
  end
end
