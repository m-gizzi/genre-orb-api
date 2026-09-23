# frozen_string_literal: true

require "rails_helper"

RSpec.describe PlaylistVersions::SweepCursor do
  # The suite's default client answers every read with Redis's "no such key" sentinel,
  # which is the case `read` has to clamp rather than the one it has to round-trip.
  it "reads zero against the suite's absent-key client" do
    expect(described_class.read).to eq(0)
  end

  context "with a store that reads back what was written" do
    let(:store) { {} }
    let(:redis) { instance_double(RedisClient) }

    before do
      allow(redis).to receive(:call) do |command, key, value, *|
        case command
        when "GET" then store[key]
        when "SET" then store[key] = value.to_s
        when "DEL" then store.delete(key)
        end
      end
      stub_app_redis(redis)
    end

    it "reads back what it wrote" do
      described_class.write(4_200)

      expect(described_class.read).to eq(4_200)
    end

    it "reads zero when nothing has been written" do
      expect(described_class.read).to eq(0)
    end

    it "reads zero once cleared" do
      described_class.write(4_200)
      described_class.clear

      expect(described_class.read).to eq(0)
    end

    it "clamps a negative value rather than skipping playlists" do
      store[described_class::KEY] = "-2"

      expect(described_class.read).to eq(0)
    end

    it "clamps a value that is not a number at all" do
      store[described_class::KEY] = "garbage"

      expect(described_class.read).to eq(0)
    end
  end
end
