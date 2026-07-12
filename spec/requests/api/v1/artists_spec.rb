# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::Artists" do
  let(:user) { create(:user) }

  def create_library_artist(metadata_fetched_at: nil, **attrs)
    playlist = create(:playlist, user: user)
    version = create(:playlist_version, playlist: playlist)
    playlist.update!(current_version: version)
    track = create(:track)
    create(:playlist_version_track, playlist_version: version, track: track)
    artist = create(:artist, metadata_fetched_at: metadata_fetched_at, **attrs)
    create(:track_artist, track: track, artist: artist)
    artist
  end

  describe "GET /api/v1/artists" do
    context "when not authenticated" do
      it "returns 401 unauthorized" do
        get "/api/v1/artists"
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context "when authenticated" do
      before { sign_in user }

      it "returns library artists with metadata-derived fields and a meta envelope" do
        artist = create_library_artist(
          name: "Slayer",
          metadata: { "genres" => ["thrash"], "followers" => 100, "popularity" => 70 },
        )
        create(:artist, name: "Not In Library")

        get "/api/v1/artists"

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body["data"].pluck("id")).to contain_exactly(artist.id)
        expect(response.parsed_body["data"].first).to include(
          "name" => "Slayer", "genres" => ["thrash"], "followers" => 100, "popularity" => 70,
        )
        expect(response.parsed_body["meta"]).to include("total" => 1)
      end

      it "filters by name search" do
        slayer = create_library_artist(name: "Slayer")
        create_library_artist(name: "Metallica")

        get "/api/v1/artists", params: { search: "slay" }

        expect(response.parsed_body["data"].pluck("id")).to contain_exactly(slayer.id)
      end
    end
  end

  describe "GET /api/v1/artists/:id" do
    before { sign_in user }

    it "returns the artist with its library albums" do
      artist = create(
        :artist,
        name: "Slayer",
        metadata: { "genres" => ["thrash"], "followers" => 100, "popularity" => 70 },
      )
      album = create(:album, title: "Reign in Blood")
      create(:album_artist, album: album, artist: artist)

      playlist = create(:playlist, user: user)
      version = create(:playlist_version, playlist: playlist)
      playlist.update!(current_version: version)
      track = create(:track, album: album)
      create(:playlist_version_track, playlist_version: version, track: track)
      create(:track_artist, track: track, artist: artist)

      get "/api/v1/artists/#{artist.id}"

      data = response.parsed_body["data"]
      expect(response).to have_http_status(:ok)
      expect(data).to include("id" => artist.id, "name" => "Slayer", "genres" => ["thrash"])
      expect(data["albums"].pluck("id")).to contain_exactly(album.id)
    end

    it "returns 404 for an artist outside the user's library" do
      get "/api/v1/artists/#{create(:artist).id}"

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "GET /api/v1/artists/sync_status" do
    context "when not authenticated" do
      it "returns 401 unauthorized" do
        get "/api/v1/artists/sync_status"
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context "when authenticated" do
      before { sign_in user }

      it "returns 200 OK" do
        get "/api/v1/artists/sync_status"
        expect(response).to have_http_status(:ok)
      end

      it "returns has_active_sync false when no sessions" do
        get "/api/v1/artists/sync_status"
        expect(response.parsed_body.dig("data", "has_active_sync")).to be(false)
      end

      it "returns has_active_sync true when a session is active" do
        create(:artist_metadata_session, user: user)

        get "/api/v1/artists/sync_status"
        expect(response.parsed_body.dig("data", "has_active_sync")).to be(true)
      end

      it "returns current_session details" do
        session = create(:artist_metadata_session, user: user)

        get "/api/v1/artists/sync_status"
        current = response.parsed_body.dig("data", "current_session")

        expect(current["id"]).to eq(session.id)
        expect(current["status"]).to eq("running")
        expect(current["progress"]).to be_present
      end

      it "returns artist counts scoped to the user's current library" do
        create_library_artist(metadata_fetched_at: nil)
        create_library_artist(metadata_fetched_at: nil)
        create_library_artist(metadata_fetched_at: 1.day.ago)
        create(:artist, metadata_fetched_at: nil)

        get "/api/v1/artists/sync_status"
        data = response.parsed_body["data"]

        expect(data["artists_total"]).to eq(3)
        expect(data["artists_synced"]).to eq(1)
      end

      it "returns rate limit status" do
        allow(SyncRateLimitState).to receive(:user_paused?).with(user.id).and_return(true)
        allow(SyncRateLimitState).to receive(:user_resume_at).with(user.id).and_return(Time.current + 60)

        get "/api/v1/artists/sync_status"
        data = response.parsed_body["data"]

        expect(data["rate_limited"]).to be(true)
        expect(data["rate_limit_resume_at"]).to be_present
      end
    end
  end

  describe "POST /api/v1/artists/sync" do
    context "when not authenticated" do
      it "returns 401 unauthorized" do
        post "/api/v1/artists/sync"
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context "when authenticated" do
      before { sign_in user }

      context "without Spotify connection" do
        it "returns 422 unprocessable_content" do
          post "/api/v1/artists/sync"
          expect(response).to have_http_status(:unprocessable_content)
        end

        it "returns an error message" do
          post "/api/v1/artists/sync"
          expect(response.parsed_body["errors"].first["message"]).to eq("Spotify not connected")
        end
      end

      context "with Spotify connection" do
        before { create(:service_connection, user: user) }

        context "when no artists need metadata" do
          it "returns 422 unprocessable_content" do
            post "/api/v1/artists/sync"
            expect(response).to have_http_status(:unprocessable_content)
          end

          it "returns an error message" do
            post "/api/v1/artists/sync"
            expect(response.parsed_body["errors"].first["message"]).to eq("No artists need metadata sync")
          end
        end

        context "when artists need metadata" do
          before { create_library_artist(metadata_fetched_at: nil) }

          it "returns 202 accepted" do
            post "/api/v1/artists/sync"
            expect(response).to have_http_status(:accepted)
          end

          it "creates the artist metadata session synchronously" do
            expect do
              post "/api/v1/artists/sync"
            end.to change(user.artist_metadata_sessions, :count).by(1)
          end

          it "enqueues an artist batch fetch job" do
            expect do
              post "/api/v1/artists/sync"
            end.to have_enqueued_job(ArtistBatchFetchJob)
          end

          it "returns queued status" do
            post "/api/v1/artists/sync"
            expect(response.parsed_body.dig("data", "status")).to eq("queued")
          end

          it "returns the created session in the response body" do
            post "/api/v1/artists/sync"
            session = response.parsed_body.dig("data", "session")

            expect(session["id"]).to be_present
            expect(session["status"]).to eq("running")
          end

          context "when a sync is already in progress" do
            before { create(:artist_metadata_session, user: user) }

            it "returns 409 conflict" do
              post "/api/v1/artists/sync"
              expect(response).to have_http_status(:conflict)
            end

            it "returns an error message" do
              post "/api/v1/artists/sync"
              expect(response.parsed_body["errors"].first["message"]).to eq(
                "Artist metadata sync already in progress",
              )
            end
          end
        end

        context "with sync_all=true when all artists are already fetched" do
          before { create_library_artist(metadata_fetched_at: 1.day.ago) }

          it "returns 202 accepted" do
            post "/api/v1/artists/sync", params: { sync_all: true }
            expect(response).to have_http_status(:accepted)
          end

          it "creates the artist metadata session synchronously" do
            expect do
              post "/api/v1/artists/sync", params: { sync_all: true }
            end.to change(user.artist_metadata_sessions, :count).by(1)
          end
        end
      end
    end
  end
end
