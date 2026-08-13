# frozen_string_literal: true

require "rails_helper"

RSpec.describe Spotify::TokenSource do
  describe ".for" do
    it "wraps a service connection in a user token" do
      connection = create(:service_connection)

      expect(described_class.for(connection)).to be_a(Spotify::UserToken)
    end

    it "refuses a missing connection" do
      expect { described_class.for(nil) }
        .to raise_error(Spotify::AuthenticationError, /not connected/)
    end

    it "passes an existing token source through" do
      token = Spotify::AppToken.new

      expect(described_class.for(token)).to be(token)
    end
  end
end
