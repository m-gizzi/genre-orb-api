# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::Artists" do
  let(:user) { create(:user) }

  def create_library_artist(metadata_fetched_at: nil)
    playlist = create(:playlist, user: user)
    version = create(:playlist_version, playlist: playlist)
    playlist.update!(current_version: version)
    track = create(:track)
    create(:playlist_version_track, playlist_version: version, track: track)
    artist = create(:artist, metadata_fetched_at: metadata_fetched_at)
    create(:track_artist, track: track, artist: artist)
    artist
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
        expect(response.parsed_body["has_active_sync"]).to be(false)
      end

      it "returns has_active_sync true when a session is active" do
        create(:artist_metadata_session, user: user)

        get "/api/v1/artists/sync_status"
        expect(response.parsed_body["has_active_sync"]).to be(true)
      end

      it "returns current_session details" do
        session = create(:artist_metadata_session, user: user)

        get "/api/v1/artists/sync_status"
        body = response.parsed_body

        expect(body["current_session"]["id"]).to eq(session.id)
        expect(body["current_session"]["status"]).to eq("running")
        expect(body["current_session"]["progress"]).to be_present
      end

      it "returns artist counts scoped to the user's current library" do
        create_library_artist(metadata_fetched_at: nil)
        create_library_artist(metadata_fetched_at: nil)
        create_library_artist(metadata_fetched_at: 1.day.ago)
        create(:artist, metadata_fetched_at: nil)

        get "/api/v1/artists/sync_status"
        body = response.parsed_body

        expect(body["artists_total"]).to eq(3)
        expect(body["artists_synced"]).to eq(1)
      end

      it "returns rate limit status" do
        allow(SyncRateLimitState).to receive(:user_paused?).with(user.id).and_return(true)
        allow(SyncRateLimitState).to receive(:user_resume_at).with(user.id).and_return(Time.current + 60)

        get "/api/v1/artists/sync_status"
        body = response.parsed_body

        expect(body["rate_limited"]).to be(true)
        expect(body["rate_limit_resume_at"]).to be_present
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
          expect(response.parsed_body["error"]).to eq("Spotify not connected")
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
            expect(response.parsed_body["error"]).to eq("No artists need metadata sync")
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
            expect(response.parsed_body["status"]).to eq("queued")
          end

          it "returns the created session in the response body" do
            post "/api/v1/artists/sync"
            session = response.parsed_body["session"]

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
              expect(response.parsed_body["error"]).to eq("Artist metadata sync already in progress")
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
