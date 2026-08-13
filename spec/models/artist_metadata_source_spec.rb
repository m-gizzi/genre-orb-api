# frozen_string_literal: true

require "rails_helper"

RSpec.describe ArtistMetadataSource do
  subject(:row) { create(:artist_metadata_source) }

  it { is_expected.to belong_to(:artist) }

  it "shares its source values with the genre join tables" do
    expect(described_class.sources).to eq(TrackGenre.sources).and(eq(ArtistGenre.sources))
  end

  it "enforces one row per artist and source" do
    expect { create(:artist_metadata_source, artist: row.artist, source: row.source) }
      .to raise_error(ActiveRecord::RecordNotUnique)
  end

  it "allows the same artist a row per source" do
    expect { create(:artist_metadata_source, :lastfm, artist: row.artist) }.not_to raise_error
  end

  describe "the due scope" do
    it "includes a row with no retry_after" do
      expect(described_class.due).to include(row)
    end

    it "includes a row whose retry_after has passed" do
      row.update!(retry_after: 1.second.ago)

      expect(described_class.due).to include(row)
    end

    it "excludes a row whose retry_after is still ahead" do
      row.update!(retry_after: 1.hour.from_now)

      expect(described_class.due).not_to include(row)
    end

    # Written as raw SQL rather than `where(...).or(...)` precisely so this holds: `or`
    # would drop the source filter from its right-hand branch.
    it "does not leak another source's due rows into a source-scoped query" do
      other = create(:artist_metadata_source, :lastfm, artist: create(:artist), retry_after: 1.day.ago)

      expect(described_class.where(source: :musicbrainz).due).not_to include(other)
    end
  end

  describe "#record_match!" do
    it "stores the identifier and leaves the row due for its genre fetch" do
      row.record_match!(external_id: "mb-1")

      expect(row).to have_attributes(state: "matched", external_id: "mb-1", retry_after: nil, fetched_at: nil)
    end

    it "clears a previous failure" do
      row.update!(state: :errored, failure_count: 3, last_error: "boom")

      row.record_match!(external_id: "mb-1")

      expect(row).to have_attributes(failure_count: 0, last_error: nil)
    end
  end

  describe "#record_fetch!" do
    it "stamps fetched_at and schedules the refresh" do
      freeze_time do
        row.record_fetch!(external_id: "mb-1")

        expect(row).to have_attributes(state: "matched", fetched_at: Time.current,
                                       retry_after: described_class::REFRESH_TTL.from_now,)
      end
    end

    it "keeps the existing identifier when none is supplied" do
      row.update!(external_id: "mb-1")

      row.record_fetch!

      expect(row.external_id).to eq("mb-1")
    end
  end

  describe "#record_unmatched!" do
    it "schedules a long retry, since artists do get added upstream" do
      freeze_time do
        row.record_unmatched!

        expect(row).to have_attributes(state: "unmatched", retry_after: described_class::UNMATCHED_RETRY.from_now)
      end
    end

    # Reaching this from the fetch phase means the identifier is dead upstream, so the
    # next pass has to re-match rather than retry it.
    it "drops the identifier" do
      row.update!(external_id: "mb-gone")

      row.record_unmatched!

      expect(row.external_id).to be_nil
    end
  end

  describe "#record_failure!" do
    it "records the error and backs off an hour on the first failure" do
      freeze_time do
        row.record_failure!(StandardError.new("boom"))

        expect(row).to have_attributes(state: "errored", failure_count: 1, last_error: "boom",
                                       retry_after: described_class::ERROR_BACKOFF_BASE.from_now,)
      end
    end

    it "doubles the backoff per failure" do
      row.update!(failure_count: 2)

      freeze_time do
        row.record_failure!(StandardError.new("boom"))

        expect(row.retry_after).to eq((described_class::ERROR_BACKOFF_BASE * 4).from_now)
      end
    end

    it "caps the backoff" do
      row.update!(failure_count: 99)

      freeze_time do
        row.record_failure!(StandardError.new("boom"))

        expect(row.retry_after).to eq(described_class::ERROR_BACKOFF_CAP.from_now)
      end
    end

    it "truncates a huge error message to fit the column" do
      row.record_failure!(StandardError.new("x" * 500))

      expect(row.last_error.length).to eq(described_class::ERROR_LIMIT)
    end
  end
end
