# frozen_string_literal: true

require "rails_helper"

RSpec.describe Lastfm::Client do
  subject(:client) { described_class.new }

  before { described_class.instance_variable_set(:@api_key, nil) }

  after { described_class.instance_variable_set(:@api_key, nil) }

  def stub_api_key(key)
    allow(Rails.application.credentials).to receive(:dig).and_call_original
    allow(Rails.application.credentials).to receive(:dig).with(:lastfm, :api_key).and_return(key)
  end

  it "sends the api key, method and json format on every request" do
    stub_api_key("test-key")
    stub = stub_request(:get, described_class::BASE_URL)
           .with(query: { method: "artist.getTopTags", api_key: "test-key", format: "json", artist: "Gojira" })
           .to_return(status: 200, body: "{}", headers: { "Content-Type" => "application/json" })

    client.get("artist.getTopTags", params: { artist: "Gojira" })

    expect(stub).to have_been_requested
  end

  it "fails loudly when no api key is configured" do
    stub_api_key(nil)

    expect { client.get("artist.getTopTags") }.to raise_error(Lastfm::ConfigurationError, /lastfm.api_key/)
  end

  it "keeps every specific error within the ApiError family" do
    expect(Lastfm::NotFoundError.ancestors).to include(Lastfm::ApiError)
    expect(Lastfm::RateLimitError.ancestors).to include(Lastfm::ApiError)
  end

  # ConfigurationError deliberately sits outside ApiError: the drip must not record a
  # missing key as a per-artist failure and burn every row's backoff.
  it "keeps ConfigurationError outside the ApiError family" do
    expect(Lastfm::ConfigurationError.ancestors).not_to include(Lastfm::ApiError)
  end
end
