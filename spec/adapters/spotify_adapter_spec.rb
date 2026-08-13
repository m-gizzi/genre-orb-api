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
    stub = stub_request(:get, "#{Spotify::Client::BASE_URL}/#{path}")
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
        a_request(:get, "#{Spotify::Client::BASE_URL}/me")
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

  describe "#create_playlist" do
    it "posts the playlist attributes to the user's playlists endpoint" do
      stub = stub_request(:post, "#{Spotify::Client::BASE_URL}/users/spotify_user_1/playlists")
             .with(body: { name: "Metal Mix", description: "Heavy" }.to_json)
             .to_return(status: 201, body: { "id" => "new_playlist" }.to_json, headers: json_headers)

      result = adapter.create_playlist("spotify_user_1", name: "Metal Mix", description: "Heavy")

      expect(stub).to have_been_requested
      expect(result).to eq("id" => "new_playlist")
    end

    it "omits a nil description" do
      stub = stub_request(:post, "#{Spotify::Client::BASE_URL}/users/spotify_user_1/playlists")
             .with(body: { name: "Metal Mix" }.to_json)
             .to_return(status: 201, body: { "id" => "new_playlist" }.to_json, headers: json_headers)

      adapter.create_playlist("spotify_user_1", name: "Metal Mix")

      expect(stub).to have_been_requested
    end
  end

  describe "#update_playlist_details" do
    it "puts the changed attributes to the playlist endpoint" do
      stub = stub_request(:put, "#{Spotify::Client::BASE_URL}/playlists/playlist_123")
             .with(body: { name: "Renamed" }.to_json)
             .to_return(status: 200, body: "")

      adapter.update_playlist_details("playlist_123", { name: "Renamed" })

      expect(stub).to have_been_requested
    end

    it "tolerates Spotify's empty success body" do
      stub_request(:put, "#{Spotify::Client::BASE_URL}/playlists/playlist_123")
        .to_return(status: 200, body: "")

      expect { adapter.update_playlist_details("playlist_123", { name: "Renamed" }) }.not_to raise_error
    end

    it "raises ApiError when Spotify rejects the write" do
      stub_request(:put, "#{Spotify::Client::BASE_URL}/playlists/playlist_123")
        .to_return(status: 403, body: { "error" => "forbidden" }.to_json, headers: json_headers)

      expect { adapter.update_playlist_details("playlist_123", { name: "Renamed" }) }
        .to raise_error(Spotify::ApiError, /403/)
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

  describe "#playlist_snapshot_id" do
    it "asks for only the snapshot_id field" do
      stub = stub_get("playlists/playlist_123", query: { fields: "snapshot_id" }, body: { "snapshot_id" => "snap_1" })

      expect(adapter.playlist_snapshot_id("playlist_123")).to eq("snap_1")
      expect(stub).to have_been_requested
    end

    it "returns nil when Spotify omits the field" do
      stub_get("playlists/playlist_123", query: { fields: "snapshot_id" }, body: {})

      expect(adapter.playlist_snapshot_id("playlist_123")).to be_nil
    end
  end

  describe "#add_tracks_to_playlist" do
    it "posts track uris built from spotify ids" do
      stub = stub_request(:post, "#{Spotify::Client::BASE_URL}/playlists/playlist_123/tracks")
             .with(body: { uris: ["spotify:track:a", "spotify:track:b"] }.to_json)
             .to_return(status: 201, body: { "snapshot_id" => "snap_2" }.to_json, headers: json_headers)

      result = adapter.add_tracks_to_playlist("playlist_123", %w[a b])

      expect(stub).to have_been_requested
      expect(result).to eq("snapshot_id" => "snap_2")
    end

    it "raises ArgumentError when over the batch limit" do
      too_many = Array.new(described_class::TRACK_BATCH_LIMIT + 1) { |i| "id#{i}" }

      expect { adapter.add_tracks_to_playlist("playlist_123", too_many) }
        .to raise_error(ArgumentError, /Cannot add more than #{described_class::TRACK_BATCH_LIMIT}/o)
    end
  end

  describe "#remove_tracks_from_playlist" do
    it "sends a DELETE carrying the uris in its body" do
      stub = stub_request(:delete, "#{Spotify::Client::BASE_URL}/playlists/playlist_123/tracks")
             .with(body: { tracks: [{ uri: "spotify:track:a" }, { uri: "spotify:track:b" }] }.to_json)
             .to_return(status: 200, body: { "snapshot_id" => "snap_3" }.to_json, headers: json_headers)

      result = adapter.remove_tracks_from_playlist("playlist_123", %w[a b])

      expect(stub).to have_been_requested
      expect(result).to eq("snapshot_id" => "snap_3")
    end

    it "raises ArgumentError when over the batch limit" do
      too_many = Array.new(described_class::TRACK_BATCH_LIMIT + 1) { |i| "id#{i}" }

      expect { adapter.remove_tracks_from_playlist("playlist_123", too_many) }
        .to raise_error(ArgumentError, /Cannot remove more than #{described_class::TRACK_BATCH_LIMIT}/o)
    end
  end

  describe "#replace_playlist_tracks" do
    it "clears the playlist when given no uris" do
      stub = stub_request(:put, "#{Spotify::Client::BASE_URL}/playlists/playlist_123/tracks")
             .with(body: { uris: [] }.to_json)
             .to_return(status: 200, body: { "snapshot_id" => "snap_4" }.to_json, headers: json_headers)

      expect(adapter.replace_playlist_tracks("playlist_123", [])).to eq("snapshot_id" => "snap_4")
      expect(stub).to have_been_requested
    end

    it "clears and seeds in one call when given uris" do
      stub = stub_request(:put, "#{Spotify::Client::BASE_URL}/playlists/playlist_123/tracks")
             .with(body: { uris: ["spotify:track:a", "spotify:track:b"] }.to_json)
             .to_return(status: 200, body: { "snapshot_id" => "snap_5" }.to_json, headers: json_headers)

      adapter.replace_playlist_tracks("playlist_123", %w[a b])

      expect(stub).to have_been_requested
    end

    it "raises ArgumentError when over the batch limit" do
      too_many = Array.new(described_class::TRACK_BATCH_LIMIT + 1) { |i| "id#{i}" }

      expect { adapter.replace_playlist_tracks("playlist_123", too_many) }
        .to raise_error(ArgumentError, /Cannot replace more than #{described_class::TRACK_BATCH_LIMIT}/o)
    end
  end

  describe "response handling" do
    it "returns the parsed body on success" do
      stub_get("me", body: { "id" => "abc", "display_name" => "Test" })

      expect(adapter.user_profile).to eq("id" => "abc", "display_name" => "Test")
    end

    it "raises ApiError on unexpected status codes" do
      stub_get("me", status: 500, body: { "error" => "boom" })

      expect { adapter.user_profile }.to raise_error(Spotify::ApiError, /500/)
    end

    describe "rate limiting (429)" do
      it "raises RateLimitError carrying Retry-After and the user id" do
        stub_get("me", status: 429, headers: { "Retry-After" => "30" })

        expect { adapter.user_profile }.to raise_error(Spotify::RateLimitError) do |error|
          expect(error.retry_after).to eq(30)
          expect(error.user_id).to eq(user.id)
        end
      end

      it "clamps a missing Retry-After header to a positive minimum" do
        stub_get("me", status: 429, headers: {})

        expect { adapter.user_profile }.to raise_error(Spotify::RateLimitError) do |error|
          expect(error.retry_after).to eq(Spotify::RateLimitError::MIN_RETRY_AFTER)
        end
      end
    end

    describe "authentication (401)" do
      it "refreshes the token and retries once, then succeeds" do
        stub_request(:get, "#{Spotify::Client::BASE_URL}/me")
          .to_return(
            { status: 401 },
            { status: 200, body: { "id" => "abc" }.to_json, headers: json_headers },
          )
        token_stub = stub_request(:post, Spotify::TokenSource::TOKEN_URL)
                     .to_return(status: 200, body: { access_token: "refreshed_token", expires_in: 3600 }.to_json)

        expect(adapter.user_profile).to eq("id" => "abc")
        expect(token_stub).to have_been_requested
        expect(service_connection.reload.access_token).to eq("refreshed_token")
      end

      it "verify_connection returns false when refresh cannot recover" do
        stub_request(:get, "#{Spotify::Client::BASE_URL}/me").to_return(status: 401)
        stub_request(:post, Spotify::TokenSource::TOKEN_URL)
          .to_return(status: 200, body: { access_token: "refreshed_token", expires_in: 3600 }.to_json)

        expect(adapter.verify_connection).to be(false)
      end
    end
  end

  describe "proactive token refresh" do
    it "refreshes before the request when the token is expiring soon" do
      service_connection.update!(token_expires_at: 1.minute.from_now)
      token_stub = stub_request(:post, Spotify::TokenSource::TOKEN_URL)
                   .to_return(status: 200, body: { access_token: "refreshed_token", expires_in: 3600 }.to_json)
      stub_get("me", body: { "id" => "abc" })

      adapter.user_profile

      expect(token_stub).to have_been_requested
    end
  end
end
