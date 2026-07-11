# frozen_string_literal: true

require "rails_helper"

RSpec.describe SpotifyAdapter do
  let(:user) { create(:user) }
  let(:service_connection) do
    create(:service_connection, user: user, access_token: "test_token", token_expires_at: 1.hour.from_now)
  end
  let(:adapter) { described_class.new(service_connection) }

  let(:json_headers) { { "Content-Type" => "application/json" } }

  def stub_get(path, query: nil, status: 200, body: {}, headers: json_headers)
    stub = stub_request(:get, "#{described_class::BASE_URL}/#{path}")
    stub = stub.with(query: query) if query
    stub.to_return(status: status, body: body.to_json, headers: headers)
  end

  describe "request URL building" do
    it "prefixes the /v1 path segment (relative path, no leading slash)" do
      stub = stub_get("me", body: { "id" => "abc" })

      adapter.user_profile

      expect(stub).to have_been_requested
    end

    it "sends the bearer token on every request" do
      stub_get("me", body: { "id" => "abc" })

      adapter.user_profile

      expect(
        a_request(:get, "#{described_class::BASE_URL}/me")
          .with(headers: { "Authorization" => "Bearer test_token" }),
      ).to have_been_requested
    end

    it "requests playlists with pagination params" do
      stub = stub_get("me/playlists", query: { limit: 50, offset: 0 }, body: { "items" => [] })

      adapter.playlists(limit: 50, offset: 0)

      expect(stub).to have_been_requested
    end

    it "requests a single playlist by id" do
      stub = stub_get("playlists/playlist_123", body: { "id" => "playlist_123" })

      adapter.playlist("playlist_123")

      expect(stub).to have_been_requested
    end

    it "requests playlist tracks with pagination params" do
      stub = stub_get("playlists/playlist_123/tracks", query: { limit: 100, offset: 100 }, body: { "items" => [] })

      adapter.playlist_tracks("playlist_123", limit: 100, offset: 100)

      expect(stub).to have_been_requested
    end

    it "requests liked songs with pagination params" do
      stub = stub_get("me/tracks", query: { limit: 50, offset: 0 }, body: { "items" => [] })

      adapter.liked_songs(limit: 50, offset: 0)

      expect(stub).to have_been_requested
    end
  end

  describe "#artists" do
    it "joins ids into a comma-separated query param" do
      stub = stub_get("artists", query: { ids: "a,b,c" }, body: { "artists" => [] })

      adapter.artists(%w[a b c])

      expect(stub).to have_been_requested
    end

    it "raises ArgumentError when over the batch limit" do
      too_many = Array.new(described_class::ARTIST_BATCH_LIMIT + 1) { |i| "id#{i}" }

      expect { adapter.artists(too_many) }
        .to raise_error(ArgumentError, /Cannot fetch more than #{described_class::ARTIST_BATCH_LIMIT}/o)
    end

    it "allows exactly the batch limit" do
      ids = Array.new(described_class::ARTIST_BATCH_LIMIT) { |i| "id#{i}" }
      stub_get("artists", query: { ids: ids.join(",") }, body: { "artists" => [] })

      expect { adapter.artists(ids) }.not_to raise_error
    end
  end

  describe "response handling" do
    it "returns the parsed body on success" do
      stub_get("me", body: { "id" => "abc", "display_name" => "Test" })

      expect(adapter.user_profile).to eq("id" => "abc", "display_name" => "Test")
    end

    it "raises ApiError on unexpected status codes" do
      stub_get("me", status: 500, body: { "error" => "boom" })

      expect { adapter.user_profile }.to raise_error(described_class::ApiError, /500/)
    end

    describe "rate limiting (429)" do
      it "raises RateLimitError carrying Retry-After and the user id" do
        stub_get("me", status: 429, headers: { "Retry-After" => "30" })

        expect { adapter.user_profile }.to raise_error(described_class::RateLimitError) do |error|
          expect(error.retry_after).to eq(30)
          expect(error.user_id).to eq(user.id)
        end
      end

      it "clamps a missing Retry-After header to a positive minimum" do
        stub_get("me", status: 429, headers: {})

        expect { adapter.user_profile }.to raise_error(described_class::RateLimitError) do |error|
          expect(error.retry_after).to eq(described_class::RateLimitError::MIN_RETRY_AFTER)
        end
      end
    end

    describe "authentication (401)" do
      it "refreshes the token and retries once, then succeeds" do
        stub_request(:get, "#{described_class::BASE_URL}/me")
          .to_return(
            { status: 401 },
            { status: 200, body: { "id" => "abc" }.to_json, headers: json_headers },
          )
        token_stub = stub_request(:post, described_class::TOKEN_URL)
                     .to_return(status: 200, body: { access_token: "refreshed_token", expires_in: 3600 }.to_json)

        expect(adapter.user_profile).to eq("id" => "abc")
        expect(token_stub).to have_been_requested
        expect(service_connection.reload.access_token).to eq("refreshed_token")
      end

      it "verify_connection returns false when refresh cannot recover" do
        stub_request(:get, "#{described_class::BASE_URL}/me").to_return(status: 401)
        stub_request(:post, described_class::TOKEN_URL)
          .to_return(status: 200, body: { access_token: "refreshed_token", expires_in: 3600 }.to_json)

        expect(adapter.verify_connection).to be(false)
      end
    end
  end

  describe "proactive token refresh" do
    it "refreshes before the request when the token is expiring soon" do
      service_connection.update!(token_expires_at: 1.minute.from_now)
      token_stub = stub_request(:post, described_class::TOKEN_URL)
                   .to_return(status: 200, body: { access_token: "refreshed_token", expires_in: 3600 }.to_json)
      stub_get("me", body: { "id" => "abc" })

      adapter.user_profile

      expect(token_stub).to have_been_requested
    end
  end
end
