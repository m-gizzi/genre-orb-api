# frozen_string_literal: true

require "rails_helper"

RSpec.describe Enrichment::Lock do
  let(:redis) { instance_double(RedisClient) }

  before { stub_app_redis(redis) }

  def allow_set(reply)
    allow(redis).to receive(:call).with("SET", any_args).and_return(reply)
    allow(redis).to receive(:call).with("DEL", any_args).and_return(1)
  end

  it "yields and reports :ran when it takes the lock" do
    allow_set("OK")
    ran = false

    expect(described_class.acquire("musicbrainz", ttl: 90) { ran = true }).to eq(:ran)
    expect(ran).to be(true)
  end

  it "sets the key NX with the ttl, so two ticks cannot overlap" do
    allow_set("OK")

    described_class.acquire("musicbrainz", ttl: 90) { nil }

    expect(redis).to have_received(:call)
      .with("SET", "#{described_class::KEY_PREFIX}:musicbrainz", anything, "NX", "EX", 90)
  end

  it "does not yield and reports :busy when the key is already held" do
    allow_set(nil)
    ran = false

    expect(described_class.acquire("musicbrainz", ttl: 90) { ran = true }).to eq(:busy)
    expect(ran).to be(false)
  end

  it "releases the key afterwards" do
    allow_set("OK")

    described_class.acquire("lastfm", ttl: 90) { nil }

    expect(redis).to have_received(:call).with("DEL", "#{described_class::KEY_PREFIX}:lastfm")
  end

  it "releases the key even when the block raises" do
    allow_set("OK")

    expect { described_class.acquire("lastfm", ttl: 90) { raise "boom" } }.to raise_error("boom")
    expect(redis).to have_received(:call).with("DEL", "#{described_class::KEY_PREFIX}:lastfm")
  end

  it "keys each source separately so they never block one another" do
    allow_set("OK")

    described_class.acquire("musicbrainz", ttl: 90) { nil }
    described_class.acquire("lastfm", ttl: 90) { nil }

    expect(redis).to have_received(:call)
      .with("SET", "#{described_class::KEY_PREFIX}:lastfm", anything, "NX", "EX", 90)
  end
end
