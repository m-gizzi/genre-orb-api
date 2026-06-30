# frozen_string_literal: true

require "rails_helper"

RSpec.describe SpotifyOauthService do
  let(:auth_hash) do
    {
      "uid" => "spotify_user_123",
      "info" => {
        "name" => "Test User",
        "email" => "spotify@example.com",
        "images" => [{ "url" => "https://example.com/avatar.jpg" }],
        "country" => "US",
        "product" => "premium",
      },
      "credentials" => {
        "token" => "access_token_abc",
        "refresh_token" => "refresh_token_xyz",
        "expires_at" => 1.hour.from_now.to_i,
      },
      "extra" => {
        "raw_info" => {
          "external_urls" => { "spotify" => "https://open.spotify.com/user/spotify_user_123" },
        },
      },
    }
  end

  describe "#call" do
    subject(:result) { described_class.new(current_user, auth_hash).call }

    context "when user is logged in" do
      let(:current_user) { create(:user) }

      context "without an existing Spotify connection" do
        it "returns success" do
          expect(result.success?).to be true
        end

        it "returns the current user" do
          expect(result.user).to eq(current_user)
        end

        it "creates a service connection" do
          expect { result }.to change(ServiceConnection, :count).by(1)
        end

        it "stores the correct tokens" do
          connection = result.service_connection
          expect(connection.access_token).to eq("access_token_abc")
          expect(connection.refresh_token).to eq("refresh_token_xyz")
        end

        it "stores the profile data" do
          connection = result.service_connection
          expect(connection.profile_data["display_name"]).to eq("Test User")
          expect(connection.profile_data["email"]).to eq("spotify@example.com")
        end
      end

      context "with an existing Spotify connection" do
        let!(:existing_connection) do
          create(:service_connection, user: current_user, service_type: :spotify, service_user_id: "spotify_user_123")
        end

        it "returns success" do
          expect(result.success?).to be true
        end

        it "updates the existing connection" do
          expect { result }.not_to change(ServiceConnection, :count)
          existing_connection.reload
          expect(existing_connection.access_token).to eq("access_token_abc")
        end
      end

      context "when the Spotify account is linked to another user" do
        let(:other_user) { create(:user) }

        before do
          create(:service_connection, user: other_user, service_type: :spotify, service_user_id: "spotify_user_123")
        end

        it "returns failure" do
          expect(result.success?).to be false
        end

        it "returns an appropriate error message" do
          expect(result.error).to include("already linked")
        end
      end
    end

    context "when user is not logged in" do
      let(:current_user) { nil }

      context "when the Spotify account is not linked to any user" do
        context "when a user with the Spotify email exists" do
          let!(:existing_user) { create(:user, email: "spotify@example.com") }

          it "returns success" do
            expect(result.success?).to be true
          end

          it "returns the existing user" do
            expect(result.user).to eq(existing_user)
          end

          it "creates a service connection for the existing user" do
            expect(result.service_connection.user).to eq(existing_user)
          end
        end

        context "when no user with the Spotify email exists" do
          it "returns success" do
            expect(result.success?).to be true
          end

          it "creates a new user" do
            expect { result }.to change(User, :count).by(1)
          end

          it "sets the new user's email from Spotify" do
            expect(result.user.email).to eq("spotify@example.com")
          end

          it "sets registration_source to spotify" do
            expect(result.user.registration_source).to eq("spotify")
          end

          it "creates a service connection for the new user" do
            expect(result.service_connection.user).to eq(result.user)
          end
        end
      end

      context "when the Spotify account is already linked to a user" do
        let(:linked_user) { create(:user) }

        before do
          create(:service_connection, user: linked_user, service_type: :spotify, service_user_id: "spotify_user_123")
        end

        it "returns success" do
          expect(result.success?).to be true
        end

        it "returns the linked user" do
          expect(result.user).to eq(linked_user)
        end

        it "updates the existing connection" do
          expect { result }.not_to change(ServiceConnection, :count)
        end
      end
    end
  end
end
