# frozen_string_literal: true

require "rails_helper"

RSpec.describe Spotify::UserToken do
  subject(:token) { described_class.new(connection) }

  let(:connection) { create(:service_connection) }

  def stub_refresh(status:, body: { access_token: "refreshed", expires_in: 3600 }.to_json)
    stub_request(:post, Spotify::TokenSource::TOKEN_URL).to_return(status: status, body: body)
  end

  it "stores the refreshed token" do
    stub_refresh(status: 200)

    token.refresh!

    expect(connection.reload.access_token).to eq("refreshed")
  end

  it "keeps the old refresh token when Spotify does not rotate one" do
    original = connection.refresh_token
    stub_refresh(status: 200)

    token.refresh!

    expect(connection.reload.refresh_token).to eq(original)
  end

  # Spotify answers a revoked or rotated-away grant with 400 invalid_grant.
  it "flags a reconnect when the grant is gone" do
    stub_refresh(status: 400, body: '{"error":"invalid_grant"}')

    expect { token.refresh! }.to raise_error(Spotify::ReauthRequiredError)
    expect(connection.reload).to have_attributes(needs_reauth: true, last_auth_error_at: be_present)
  end

  it "flags a reconnect when there is no refresh token at all" do
    connection.update!(refresh_token: nil)

    expect { token.refresh! }.to raise_error(Spotify::ReauthRequiredError)
    expect(connection.reload.needs_reauth).to be(true)
  end

  it "treats a Spotify outage as retryable and leaves the connection alone" do
    stub_refresh(status: 503)

    expect { token.refresh! }.to raise_error(Spotify::TokenRefreshError)
    expect(connection.reload.needs_reauth).to be(false)
  end

  it "does not classify a server error as needing reauthorization" do
    stub_refresh(status: 503)

    expect { token.refresh! }.not_to raise_error(Spotify::ReauthRequiredError)
  end
end
