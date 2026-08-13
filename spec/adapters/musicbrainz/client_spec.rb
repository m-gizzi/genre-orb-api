# frozen_string_literal: true

require "rails_helper"

RSpec.describe Musicbrainz::Client do
  subject(:client) { described_class.new }

  let(:json_headers) { { "Content-Type" => "application/json" } }

  # The class memoizes both, so a spec that changes the credential has to clear it.
  before { described_class.instance_variable_set(:@user_agent, nil) }

  after { described_class.instance_variable_set(:@user_agent, nil) }

  def stub_contact(contact)
    allow(Rails.application.credentials).to receive(:dig).and_call_original
    allow(Rails.application.credentials).to receive(:dig).with(:musicbrainz, :contact).and_return(contact)
  end

  describe "the User-Agent" do
    # MusicBrainz throttles anonymous user-agents far harder than 1 req/s, so this is
    # a requirement rather than politeness.
    it "identifies the app and a contact" do
      stub_contact("dev@example.com")
      stub_request(:get, "#{described_class::BASE_URL}/artist/mb-1?fmt=json")
        .to_return(status: 200, body: "{}", headers: json_headers)

      client.get("artist/mb-1")

      expect(WebMock).to have_requested(:get, %r{/artist/mb-1})
        .with(headers: { "User-Agent" => "GenreOrb/#{described_class::VERSION} ( dev@example.com )" })
    end

    it "fails loudly when no contact is configured rather than sending an anonymous agent" do
      stub_contact(nil)

      expect { client.get("artist/mb-1") }
        .to raise_error(Musicbrainz::ConfigurationError, /musicbrainz.contact/)
    end
  end

  describe "status mapping" do
    before { stub_contact("dev@example.com") }

    def stub_status(status, body: {})
      stub_request(:get, "#{described_class::BASE_URL}/artist/mb-1?fmt=json")
        .to_return(status: status, body: body.to_json, headers: json_headers)
    end

    it "returns the parsed body on success" do
      stub_status(200, body: { "id" => "mb-1" })

      expect(client.get("artist/mb-1")).to eq("id" => "mb-1")
    end

    it "always asks for json" do
      stub = stub_status(200)

      client.get("artist/mb-1")

      expect(stub).to have_been_requested
    end

    it "raises NotFoundError on 404" do
      stub_status(404)

      expect { client.get("artist/mb-1") }.to raise_error(Musicbrainz::NotFoundError)
    end

    # MusicBrainz signals throttling with a bare 503 and no Retry-After.
    it "raises RateLimitError on 503, carrying its own backoff" do
      stub_status(503)

      expect { client.get("artist/mb-1") }.to raise_error(Musicbrainz::RateLimitError) do |error|
        expect(error.retry_after).to eq(Musicbrainz::RateLimitError::RETRY_AFTER)
      end
    end

    it "raises ApiError on anything else" do
      stub_status(400, body: { "error" => "Invalid mbid." })

      expect { client.get("artist/mb-1") }.to raise_error(Musicbrainz::ApiError, /400/)
    end

    # NotFoundError and RateLimitError both descend from ApiError so a caller can
    # rescue the family, and the drip can still tell "absent" from "slow down".
    it "keeps both specific errors within the ApiError family" do
      expect(Musicbrainz::NotFoundError.ancestors).to include(Musicbrainz::ApiError)
      expect(Musicbrainz::RateLimitError.ancestors).to include(Musicbrainz::ApiError)
    end
  end
end
