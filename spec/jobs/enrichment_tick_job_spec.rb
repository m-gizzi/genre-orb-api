# frozen_string_literal: true

require "rails_helper"

RSpec.describe EnrichmentTickJob do
  let(:drip) { instance_double(Enrichment::Drip, call: Enrichment::Drip::Result.new) }

  before { allow(Enrichment::Drip).to receive(:for).and_return(drip) }

  it "runs the drip with the MusicBrainz strategy" do
    described_class.perform_now("musicbrainz")

    expect(Enrichment::Drip).to have_received(:for)
      .with(an_instance_of(Enrichment::MusicbrainzStrategy), any_args)
  end

  it "runs the drip with the Last.fm strategy" do
    described_class.perform_now("lastfm")

    expect(Enrichment::Drip).to have_received(:for)
      .with(an_instance_of(Enrichment::LastfmStrategy), any_args)
  end

  it "bounds the tick with the budget" do
    freeze_time do
      described_class.perform_now("musicbrainz")

      expect(Enrichment::Drip).to have_received(:for)
        .with(anything, deadline: described_class::TICK_BUDGET.from_now)
    end
  end

  it "skips the tick when another one still holds the lock" do
    allow(Enrichment::Lock).to receive(:acquire).and_return(:busy)

    described_class.perform_now("musicbrainz")

    expect(drip).not_to have_received(:call)
  end

  it "takes a lock named for the source" do
    allow(Enrichment::Lock).to receive(:acquire).and_return(:busy)

    described_class.perform_now("lastfm")

    expect(Enrichment::Lock).to have_received(:acquire).with("lastfm", ttl: described_class::LOCK_TTL)
  end

  # retry: false, so a poisoned tick has to be swallowed — the next one is a minute away.
  it "swallows an unexpected failure rather than taking the drip down" do
    allow(drip).to receive(:call).and_raise(Musicbrainz::ConfigurationError, "no contact configured")

    expect { described_class.perform_now("musicbrainz") }.not_to raise_error
  end

  it "swallows an unknown source" do
    expect { described_class.perform_now("discogs") }.not_to raise_error
  end

  it "does not retry" do
    expect(described_class.sidekiq_options["retry"]).to be(false)
  end

  # The metadata queue is starved whenever sync is non-empty, which for a nightly
  # library sync would be hours.
  it "runs on the enrichment queue" do
    expect(described_class.new("musicbrainz").queue_name).to eq("enrichment")
  end
end
