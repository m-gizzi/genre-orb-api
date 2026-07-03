# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Auth::Spotify" do
  describe "DELETE /auth/spotify" do
    context "when user is not authenticated" do
      it "returns 401 unauthorized" do
        delete "/auth/spotify"
        expect(response).to have_http_status(:unauthorized)
      end

      it "does not destroy any service connections" do
        expect do
          delete "/auth/spotify"
        end.not_to change(ServiceConnection, :count)
      end
    end

    context "when user is authenticated" do
      let(:user) { create(:user) }

      before do
        sign_in user
      end

      context "with a Spotify connection" do
        before { create(:service_connection, user: user, service_type: :spotify) }

        it "returns 200 OK" do
          delete "/auth/spotify"
          expect(response).to have_http_status(:ok)
        end

        it "returns a success message" do
          delete "/auth/spotify"
          expect(response.parsed_body).to eq({ "message" => "Spotify account disconnected" })
        end

        it "destroys the Spotify connection" do
          expect do
            delete "/auth/spotify"
          end.to change(ServiceConnection, :count).by(-1)
        end

        it "removes the connection from the user" do
          delete "/auth/spotify"
          expect(user.reload.spotify_connection).to be_nil
        end

        it "only destroys the user's own connection" do
          other_connection = create(:service_connection, user: create(:user), service_type: :spotify)

          expect { delete "/auth/spotify" }.to change(ServiceConnection, :count).by(-1)
          expect(ServiceConnection.exists?(other_connection.id)).to be true
        end
      end

      context "without a Spotify connection" do
        it "returns 404 not found" do
          delete "/auth/spotify"
          expect(response).to have_http_status(:not_found)
        end

        it "returns an error message" do
          delete "/auth/spotify"
          expect(response.parsed_body).to eq({ "error" => "No Spotify account connected" })
        end

        it "does not create or destroy any connections" do
          expect do
            delete "/auth/spotify"
          end.not_to change(ServiceConnection, :count)
        end
      end

      context "when the connection was already destroyed" do
        let(:connection) { create(:service_connection, user: user, service_type: :spotify) }

        it "returns 404 not found" do
          connection.destroy!

          delete "/auth/spotify"
          expect(response).to have_http_status(:not_found)
        end
      end
    end
  end
end
