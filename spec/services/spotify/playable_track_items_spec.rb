# frozen_string_literal: true

require "rails_helper"

RSpec.describe Spotify::PlayableTrackItems do
  def item(overrides = {})
    { "track" => { "id" => "t", "name" => "Song", "duration_ms" => 1000 }.merge(overrides) }
  end

  describe "#call" do
    it "keeps playable tracks" do
      items = [item]

      expect(described_class.new(items).call).to eq(items)
    end

    it "rejects items with no track id, blank title, zero duration, or a non-track type" do
      rejected = [
        { "track" => nil },
        item("id" => nil),
        item("name" => ""),
        item("duration_ms" => 0),
        item("type" => "episode"),
      ]

      expect(described_class.new(rejected).call).to be_empty
    end

    it "keeps a track whose type is explicitly track" do
      expect(described_class.new([item("type" => "track")]).call.size).to eq(1)
    end

    it "logs a per-reason count of what it skipped" do
      allow(Rails.logger).to receive(:info)

      described_class.new([item, item("name" => ""), item("type" => "episode")]).call

      expect(Rails.logger).to have_received(:info)
        .with("Spotify sync skipped 2 unplayable item(s): blank_title=1 not_a_track=1")
    end

    it "does not log when nothing was skipped" do
      allow(Rails.logger).to receive(:info)

      described_class.new([item]).call

      expect(Rails.logger).not_to have_received(:info)
    end
  end
end
