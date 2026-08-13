# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Auth::Users" do
  describe "GET /auth/me" do
    let(:user) { create(:user) }

    before { sign_in user }

    it "reports a healthy connection" do
      create(:service_connection, user: user)

      get "/auth/me"

      expect(response.parsed_body["user"])
        .to include("spotify_connected" => true, "spotify_needs_reauth" => false)
    end

    it "reports a connection that needs reauthorizing" do
      create(:service_connection, user: user, needs_reauth: true)

      get "/auth/me"

      expect(response.parsed_body["user"]).to include("spotify_needs_reauth" => true)
    end

    it "reports no connection at all" do
      get "/auth/me"

      expect(response.parsed_body["user"])
        .to include("spotify_connected" => false, "spotify_needs_reauth" => false)
    end
  end
end
