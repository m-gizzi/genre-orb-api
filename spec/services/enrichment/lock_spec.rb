# frozen_string_literal: true

require "rails_helper"

RSpec.describe Enrichment::Lock do
  let(:redis) { instance_double(RedisClient) }

  before { stub_app_redis(redis) }

  def allow_set(reply)
    allow(redis).to receive(:call).with("SET", any_args).and_return(reply)
    allow(redis).to receive(:call).with("EVAL", any_args).and_return(1)
  end

  # SET's value argument and EVAL's last argument, in call order.
  def capture_tokens
    tokens = { set: [], eval: [] }
    allow(redis).to receive(:call).with("SET", any_args) { |*args| tokens[:set].push(args[2]) && "OK" }
    allow(redis).to receive(:call).with("EVAL", any_args) { |*args| tokens[:eval].push(args.last) && 1 }
    tokens
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

    expect(redis).to have_received(:call)
      .with("EVAL", described_class::RELEASE, 1, "#{described_class::KEY_PREFIX}:lastfm", anything)
  end

  it "releases the key even when the block raises" do
    allow_set("OK")

    expect { described_class.acquire("lastfm", ttl: 90) { raise "boom" } }.to raise_error("boom")
    expect(redis).to have_received(:call).with("EVAL", any_args)
  end

  # A tick that outran the TTL must not free the lock its successor now holds, so the
  # release is conditional on the token this tick wrote rather than a bare DEL.
  it "releases only the token it wrote" do
    tokens = capture_tokens

    described_class.acquire("lastfm", ttl: 90) { nil }

    expect(tokens[:eval]).to eq(tokens[:set])
  end

  it "writes a fresh token per acquisition, so one tick cannot release another's" do
    tokens = capture_tokens

    2.times { described_class.acquire("lastfm", ttl: 90) { nil } }

    expect(tokens[:set].uniq.size).to eq(2)
  end

  it "keys each source separately so they never block one another" do
    allow_set("OK")

    described_class.acquire("musicbrainz", ttl: 90) { nil }
    described_class.acquire("lastfm", ttl: 90) { nil }

    expect(redis).to have_received(:call)
      .with("SET", "#{described_class::KEY_PREFIX}:lastfm", anything, "NX", "EX", 90)
  end
end
