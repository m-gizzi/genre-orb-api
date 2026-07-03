# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Auth::OmniauthCallbacks" do
  let(:valid_origin) { "http://localhost:3000/oauth/callback" }
  let(:invalid_origin) { "http://evil-site.com/callback" }

  before do
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with("ALLOWED_OAUTH_ORIGINS", "").and_return("localhost:3000, example.com:8080")

    OmniAuth.config.test_mode = true
    OmniAuth.config.mock_auth[:spotify] = OmniAuth::AuthHash.new(spotify_omniauth_hash)
  end

  after do
    OmniAuth.config.test_mode = false
    OmniAuth.config.mock_auth[:spotify] = nil
  end

  describe "GET /auth/spotify/callback" do
    def get_spotify_callback(origin: valid_origin)
      get "/auth/spotify/callback", headers: { "HTTP_REFERER" => origin }, env: {
        "omniauth.auth" => OmniAuth.config.mock_auth[:spotify],
        "omniauth.origin" => origin,
      }
    end

    context "with valid origin" do
      context "when OAuth is successful" do
        let(:user) { create(:user) }

        before { sign_in user }

        it "creates a service connection" do
          expect { get_spotify_callback }.to change(ServiceConnection, :count).by(1)
        end

        it "stores the correct tokens in the connection" do
          get_spotify_callback

          connection = user.reload.spotify_connection
          expect(connection.access_token).to eq("access_token_abc")
          expect(connection.refresh_token).to eq("refresh_token_xyz")
        end
      end

      context "when OAuth is successful and user is not signed in" do
        it "creates a new user and signs them in" do
          expect { get_spotify_callback }.to change(User, :count).by(1)
          expect(response).to have_http_status(:redirect)
          expect(response.location).to include("success=true")
        end
      end

      context "when OAuth fails due to account linked to another user" do
        let(:user) { create(:user) }
        let(:other_user) { create(:user) }

        before do
          sign_in user
          create(:service_connection, user: other_user, service_type: :spotify, service_user_id: "spotify_user_123")
        end

        it "does not create a new service connection" do
          expect { get_spotify_callback }.not_to change(ServiceConnection, :count)
        end
      end
    end

    context "with invalid origin" do
      it "returns 400 bad request" do
        get_spotify_callback(origin: invalid_origin)
        expect(response).to have_http_status(:bad_request)
      end

      it "returns an empty body" do
        get_spotify_callback(origin: invalid_origin)
        expect(response.body).to be_empty
      end

      it "does not create a service connection" do
        expect { get_spotify_callback(origin: invalid_origin) }.not_to change(ServiceConnection, :count)
      end

      it "logs a warning about invalid origin" do
        allow(Rails.logger).to receive(:warn)
        get_spotify_callback(origin: invalid_origin)
        expect(Rails.logger).to have_received(:warn).with("Invalid OAuth origin attempted: #{invalid_origin}")
      end
    end

    context "with blank origin" do
      it "returns 400 bad request" do
        get_spotify_callback(origin: "")
        expect(response).to have_http_status(:bad_request)
      end
    end

    context "with nil origin" do
      it "returns 400 bad request" do
        get "/auth/spotify/callback", env: {
          "omniauth.auth" => OmniAuth.config.mock_auth[:spotify],
          "omniauth.origin" => nil,
        }
        expect(response).to have_http_status(:bad_request)
      end
    end

    context "with origin on non-standard port" do
      let(:origin_with_port) { "http://example.com:8080/callback" }

      it "allows the origin if it matches with port" do
        get_spotify_callback(origin: origin_with_port)
        expect(response).to have_http_status(:redirect)
        expect(response.location).to start_with(origin_with_port)
      end
    end

    context "with origin on default port" do
      let(:origin_default_port) { "http://localhost/callback" }

      before do
        allow(ENV).to receive(:fetch).with("ALLOWED_OAUTH_ORIGINS", "").and_return("localhost, example.com:8080")
      end

      it "allows the origin matching without port" do
        get_spotify_callback(origin: origin_default_port)
        expect(response).to have_http_status(:redirect)
      end
    end
  end
end
