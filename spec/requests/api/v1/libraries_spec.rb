# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::Libraries" do
  let(:user) { create(:user) }

  describe "GET /api/v1/library/status" do
    context "when not authenticated" do
      it "returns 401 unauthorized" do
        get "/api/v1/library/status"
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context "when authenticated" do
      before { sign_in user }

      it "returns 200 OK" do
        get "/api/v1/library/status"
        expect(response).to have_http_status(:ok)
      end

      it "returns has_active_sync false when no sessions" do
        get "/api/v1/library/status"
        expect(response.parsed_body["has_active_sync"]).to be(false)
      end

      it "returns has_active_sync true when session is active" do
        create(:sync_session, :running, user: user)

        get "/api/v1/library/status"
        expect(response.parsed_body["has_active_sync"]).to be(true)
      end

      it "returns current_session details" do
        session = create(:sync_session, :running, user: user)

        get "/api/v1/library/status"
        body = response.parsed_body

        expect(body["current_session"]["id"]).to eq(session.id)
        expect(body["current_session"]["status"]).to eq("running")
      end

      it "includes playlist progress in current_session" do
        session = create(:sync_session, :running, user: user)
        playlist = create(:playlist, user: user)
        create(:sync_session_playlist, :fetching, sync_session: session, playlist: playlist)

        get "/api/v1/library/status"
        playlists = response.parsed_body.dig("current_session", "playlists")

        expect(playlists.length).to eq(1)
        expect(playlists.first["playlist_name"]).to eq(playlist.name)
        expect(playlists.first["status"]).to eq("fetching_pages")
      end

      it "returns rate_limited status" do
        allow(SyncRateLimitState).to receive(:user_paused?).with(user.id).and_return(true)
        allow(SyncRateLimitState).to receive(:user_resume_at)
          .with(user.id)
          .and_return(Time.current + 60)

        get "/api/v1/library/status"
        body = response.parsed_body

        expect(body["rate_limited"]).to be(true)
        expect(body["rate_limit_resume_at"]).to be_present
      end

      it "returns playlists_metadata_fetched_at" do
        user.update!(playlists_metadata_fetched_at: 1.hour.ago)

        get "/api/v1/library/status"
        expect(response.parsed_body["playlists_metadata_fetched_at"]).to be_present
      end
    end
  end

  describe "POST /api/v1/library/fetch_playlists" do
    context "when not authenticated" do
      it "returns 401 unauthorized" do
        post "/api/v1/library/fetch_playlists"
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context "when authenticated" do
      before { sign_in user }

      context "without Spotify connection" do
        it "returns 422 unprocessable_content" do
          post "/api/v1/library/fetch_playlists"
          expect(response).to have_http_status(:unprocessable_content)
        end

        it "returns error message" do
          post "/api/v1/library/fetch_playlists"
          expect(response.parsed_body["error"]).to eq("Spotify not connected")
        end
      end

      context "with Spotify connection" do
        before do
          create(:service_connection, user: user)
        end

        it "returns 202 accepted" do
          post "/api/v1/library/fetch_playlists"
          expect(response).to have_http_status(:accepted)
        end

        it "enqueues FetchPlaylistsMetadataJob" do
          expect {
            post "/api/v1/library/fetch_playlists"
          }.to have_enqueued_job(FetchPlaylistsMetadataJob).with(user.id)
        end

        it "returns queued status" do
          post "/api/v1/library/fetch_playlists"
          expect(response.parsed_body["status"]).to eq("queued")
        end
      end
    end
  end

  describe "POST /api/v1/library/sync" do
    context "when not authenticated" do
      it "returns 401 unauthorized" do
        post "/api/v1/library/sync"
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context "when authenticated" do
      before { sign_in user }

      context "without Spotify connection" do
        it "returns 422 unprocessable_content" do
          post "/api/v1/library/sync"
          expect(response).to have_http_status(:unprocessable_content)
        end

        it "returns error message" do
          post "/api/v1/library/sync"
          expect(response.parsed_body["error"]).to eq("Spotify not connected")
        end
      end

      context "with Spotify connection" do
        before do
          create(:service_connection, user: user)
        end

        context "when no playlists are selected" do
          it "returns 422 unprocessable_content" do
            post "/api/v1/library/sync"
            expect(response).to have_http_status(:unprocessable_content)
          end

          it "returns error message" do
            post "/api/v1/library/sync"
            expect(response.parsed_body["error"]).to eq("No playlists selected for sync")
          end
        end

        context "when playlists are selected" do
          before do
            create(:playlist, :sync_enabled, user: user)
          end

          it "returns 202 accepted" do
            post "/api/v1/library/sync"
            expect(response).to have_http_status(:accepted)
          end

          it "enqueues LibrarySyncJob" do
            expect {
              post "/api/v1/library/sync"
            }.to have_enqueued_job(LibrarySyncJob).with(user.id)
          end

          it "returns queued status" do
            post "/api/v1/library/sync"
            expect(response.parsed_body["status"]).to eq("queued")
          end

          context "when sync is already in progress" do
            before do
              create(:sync_session, :running, user: user)
            end

            it "returns 409 conflict" do
              post "/api/v1/library/sync"
              expect(response).to have_http_status(:conflict)
            end

            it "returns error message" do
              post "/api/v1/library/sync"
              expect(response.parsed_body["error"]).to eq("Sync already in progress")
            end
          end
        end
      end
    end
  end
end
