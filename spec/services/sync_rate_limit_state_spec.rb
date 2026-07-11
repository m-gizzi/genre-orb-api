# frozen_string_literal: true

require "rails_helper"

RSpec.describe SyncRateLimitState do
  let(:user_id) { 123 }
  let(:redis) { instance_spy(RedisClient) }
  let(:pool) { instance_spy(RedisClient::Pooled) }

  before do
    allow(described_class).to receive(:redis_pool).and_return(pool)
    allow(pool).to receive(:with).and_yield(redis)
  end

  describe ".pause_user!" do
    it "sets key with expiration" do
      described_class.pause_user!(user_id, 60)

      expect(redis).to have_received(:call)
        .with("SETEX", "genre_orb:sync:rate_limit:user:#{user_id}", 60, anything)
    end

    it "converts seconds to integer" do
      described_class.pause_user!(user_id, 30.5)

      expect(redis).to have_received(:call)
        .with("SETEX", anything, 30, anything)
    end
  end

  describe ".user_paused?" do
    it "returns false when key does not exist" do
      allow(redis).to receive(:call).with("EXISTS", "genre_orb:sync:rate_limit:user:#{user_id}").and_return(0)

      expect(described_class.user_paused?(user_id)).to be(false)
    end

    it "returns true when key exists" do
      allow(redis).to receive(:call).with("EXISTS", "genre_orb:sync:rate_limit:user:#{user_id}").and_return(1)

      expect(described_class.user_paused?(user_id)).to be(true)
    end
  end

  describe ".user_resume_at" do
    it "returns nil when TTL is zero or negative" do
      allow(redis).to receive(:call).with("TTL", "genre_orb:sync:rate_limit:user:#{user_id}").and_return(-1)

      expect(described_class.user_resume_at(user_id)).to be_nil
    end

    it "returns future time when TTL is positive" do
      allow(redis).to receive(:call).with("TTL", "genre_orb:sync:rate_limit:user:#{user_id}").and_return(60)

      result = described_class.user_resume_at(user_id)
      expect(result).to be_within(2.seconds).of(Time.current + 60)
    end
  end

  describe ".wait_time_for_user" do
    it "returns 0 when TTL is negative" do
      allow(redis).to receive(:call).with("TTL", "genre_orb:sync:rate_limit:user:#{user_id}").and_return(-2)

      expect(described_class.wait_time_for_user(user_id)).to eq(0)
    end

    it "returns TTL when positive" do
      allow(redis).to receive(:call).with("TTL", "genre_orb:sync:rate_limit:user:#{user_id}").and_return(45)

      expect(described_class.wait_time_for_user(user_id)).to eq(45)
    end
  end
end
