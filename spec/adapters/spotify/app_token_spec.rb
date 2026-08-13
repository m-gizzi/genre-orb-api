# frozen_string_literal: true

require "rails_helper"

RSpec.describe Spotify::AppToken do
  subject(:token) { described_class.new }

  let(:redis) { instance_spy(RedisClient) }

  before do
    allow(AppRedis).to receive(:with) { |&block| block.call(redis) }
    allow(redis).to receive(:call).and_return(-2)
  end

  def stub_token_request(access_token: "app_token", expires_in: 3600, status: 200)
    stub_request(:post, Spotify::TokenSource::TOKEN_URL)
      .to_return(status: status, body: { access_token: access_token, expires_in: expires_in }.to_json)
  end

  it "mints a token with the client-credentials grant" do
    request = stub_token_request

    expect(token.access_token).to eq("app_token")
    expect(request.with(body: /grant_type=client_credentials/)).to have_been_requested
  end

  it "caches the minted token in Redis, short of its real expiry" do
    stub_token_request(expires_in: 3600)

    token.access_token

    expect(redis).to have_received(:call)
      .with("SETEX", described_class::CACHE_KEY, 3600 - described_class::EXPIRY_BUFFER, "app_token")
  end

  it "does not mint again while the memo is warm" do
    request = stub_token_request

    2.times { token.access_token }

    expect(request).to have_been_requested.once
  end

  it "uses a token another worker already cached" do
    allow(redis).to receive(:call).with("TTL", described_class::CACHE_KEY).and_return(600)
    allow(redis).to receive(:call).with("GET", described_class::CACHE_KEY).and_return("shared_token")
    request = stub_token_request

    expect(token.access_token).to eq("shared_token")
    expect(request).not_to have_been_requested
  end

  it "mints again once the cached token has expired" do
    stub_token_request(expires_in: 120)
    token.access_token

    travel_to(121.seconds.from_now) { token.access_token }

    expect(a_request(:post, Spotify::TokenSource::TOKEN_URL)).to have_been_made.twice
  end

  it "re-mints on refresh! even with a warm memo" do
    stub_token_request
    token.access_token

    token.refresh!

    expect(a_request(:post, Spotify::TokenSource::TOKEN_URL)).to have_been_made.twice
  end

  it "raises when Spotify rejects the app credentials" do
    stub_token_request(status: 400)

    expect { token.access_token }.to raise_error(Spotify::TokenRefreshError)
  end

  it "has no user and nothing to reauthorize" do
    expect(token.user_id).to be_nil
    expect(token.expiring_soon?).to be(false)
    expect(token.flag_needs_reauth!("anything")).to be_nil
  end
end
