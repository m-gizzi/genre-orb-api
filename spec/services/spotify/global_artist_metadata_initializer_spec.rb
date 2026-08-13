# frozen_string_literal: true

require "rails_helper"

RSpec.describe Spotify::GlobalArtistMetadataInitializer do
  subject(:result) { described_class.new.call }

  it "starts a session that belongs to nobody" do
    create(:artist, metadata_fetched_at: nil)

    expect(result).to be_started
    expect(result.session).to have_attributes(user_id: nil, status: "running", total_batches: 1)
  end

  it "enqueues one batch job per slice, with no user behind it" do
    create(:artist, metadata_fetched_at: nil)

    expect { described_class.new.call }
      .to have_enqueued_job(ArtistBatchFetchJob).with(hash_excluding(:user_id))
  end

  it "covers artists from every user's library in one pass" do
    artists = create_list(:artist, 2, metadata_fetched_at: nil)

    expect(result.batches.flatten).to match_array(artists.map(&:id))
  end

  it "links the session to the scheduled run that asked for it" do
    create(:artist, metadata_fetched_at: nil)
    run = create(:scheduled_run)

    expect(described_class.new(scheduled_run: run).call.session.scheduled_run).to eq(run)
  end

  describe "which artists it picks up" do
    it "includes one whose metadata has gone stale" do
      create(:artist, metadata_fetched_at: (Artist::METADATA_TTL + 1.day).ago)

      expect(result).to be_started
    end

    it "skips one fetched inside the TTL" do
      create(:artist, metadata_fetched_at: (Artist::METADATA_TTL - 1.day).ago)

      expect(result.outcome).to eq(:no_artists)
    end

    it "takes the stalest first" do
      freshest = create(:artist, metadata_fetched_at: 8.days.ago)
      stalest = create(:artist, metadata_fetched_at: 90.days.ago)
      never = create(:artist, metadata_fetched_at: nil)

      expect(result.batches.flatten).to eq([never.id, stalest.id, freshest.id])
    end

    it "caps how much a single run takes on" do
      stub_const("#{described_class}::BATCH_SIZE", 1)
      stub_const("#{described_class}::MAX_BATCHES_PER_RUN", 2)
      create_list(:artist, 3, metadata_fetched_at: nil)

      expect(result.batches.size).to eq(2)
    end
  end

  it "refuses a second global session while one is active" do
    create(:artist, metadata_fetched_at: nil)
    create(:artist_metadata_session, user: nil, status: :running)

    expect(result.outcome).to eq(:already_in_progress)
  end

  it "is unaffected by a user's own manual session" do
    create(:artist, metadata_fetched_at: nil)
    create(:artist_metadata_session, status: :running)

    expect(result).to be_started
  end

  it "reports no artists when everything is current" do
    create(:artist, metadata_fetched_at: 1.hour.ago)

    expect(result.outcome).to eq(:no_artists)
  end
end
