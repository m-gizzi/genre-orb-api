# frozen_string_literal: true

require "rails_helper"

RSpec.describe ServiceConnection do
  describe "#token_expired?" do
    subject { connection.token_expired? }

    context "when token_expires_at is in the past" do
      let(:connection) { build(:service_connection, token_expires_at: 1.hour.ago) }

      it { is_expected.to be true }
    end

    context "when token_expires_at is in the future" do
      let(:connection) { build(:service_connection, token_expires_at: 1.hour.from_now) }

      it { is_expected.to be false }
    end

    context "when token_expires_at is nil" do
      let(:connection) { build(:service_connection, token_expires_at: nil) }

      it { is_expected.to be true }
    end
  end

  describe "#token_expiring_soon?" do
    subject { connection.token_expiring_soon?(buffer: 5.minutes) }

    context "when token expires within buffer time" do
      let(:connection) { build(:service_connection, token_expires_at: 3.minutes.from_now) }

      it { is_expected.to be true }
    end

    context "when token expires after buffer time" do
      let(:connection) { build(:service_connection, token_expires_at: 10.minutes.from_now) }

      it { is_expected.to be false }
    end

    context "when token_expires_at is nil" do
      let(:connection) { build(:service_connection, token_expires_at: nil) }

      it { is_expected.to be true }
    end
  end
end
