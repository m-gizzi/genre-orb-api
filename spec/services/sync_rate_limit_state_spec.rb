# frozen_string_literal: true

require "rails_helper"

RSpec.describe SyncRateLimitState do
  let(:user_id) { 123 }
  let(:user_key) { "genre_orb:sync:rate_limit:user:#{user_id}" }
  let(:redis) { instance_spy(RedisClient) }

  before do
    allow(AppRedis).to receive(:with) { |&block| block.call(redis) }
    allow(redis).to receive(:call).and_return(-2)
  end

  def stub_ttl(key, seconds)
    allow(redis).to receive(:call).with("TTL", key).and_return(seconds)
  end

  describe ".pause!" do
    it "sets the user's key with expiration" do
      described_class.pause!(user_id, 60)

      expect(redis).to have_received(:call).with("SETEX", user_key, 60, anything)
    end

    it "converts seconds to integer" do
      described_class.pause!(user_id, 30.5)

      expect(redis).to have_received(:call).with("SETEX", anything, 30, anything)
    end

    it "pauses globally when there is no user behind the request" do
      described_class.pause!(nil, 60)

      expect(redis).to have_received(:call).with("SETEX", described_class::GLOBAL_KEY, 60, anything)
    end
  end

  describe ".user_paused?" do
    it "returns false when neither key is set" do
      expect(described_class.user_paused?(user_id)).to be(false)
    end

    it "returns true when the user's own key is set" do
      stub_ttl(user_key, 30)

      expect(described_class.user_paused?(user_id)).to be(true)
    end

    it "returns true when only the global key is set" do
      stub_ttl(described_class::GLOBAL_KEY, 30)

      expect(described_class.user_paused?(user_id)).to be(true)
    end
  end

  describe ".user_resume_at" do
    it "returns nil when TTL is zero or negative" do
      stub_ttl(user_key, -1)

      expect(described_class.user_resume_at(user_id)).to be_nil
    end

    it "returns future time when TTL is positive" do
      stub_ttl(user_key, 60)

      expect(described_class.user_resume_at(user_id)).to be_within(2.seconds).of(Time.current + 60)
    end
  end

  describe ".wait_time_for_user" do
    it "returns 0 when TTL is negative" do
      expect(described_class.wait_time_for_user(user_id)).to eq(0)
    end

    it "returns the TTL when positive" do
      stub_ttl(user_key, 45)

      expect(described_class.wait_time_for_user(user_id)).to eq(45)
    end

    it "returns the longer of the user and global pauses" do
      stub_ttl(user_key, 45)
      stub_ttl(described_class::GLOBAL_KEY, 90)

      expect(described_class.wait_time_for_user(user_id)).to eq(90)
    end
  end
end
