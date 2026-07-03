# frozen_string_literal: true

require "rails_helper"

RSpec.describe SmartPlaylist do
  describe "scopes" do
    let(:user) { create(:user) }

    describe ".enabled" do
      let!(:enabled) { create(:smart_playlist, is_enabled: true, user: user) }
      let!(:disabled) { create(:smart_playlist, is_enabled: false, user: user) }

      it "returns only enabled smart playlists" do
        expect(described_class.enabled).to contain_exactly(enabled)
        expect(described_class.enabled).not_to include(disabled)
      end
    end

    describe ".needs_evaluation" do
      let!(:never_evaluated) { create(:smart_playlist, last_evaluated_at: nil, user: user) }
      let!(:stale) { create(:smart_playlist, last_evaluated_at: 2.days.ago, user: user) }
      let!(:recent) { create(:smart_playlist, last_evaluated_at: 1.hour.ago, user: user) }
      let!(:disabled) { create(:smart_playlist, :disabled, last_evaluated_at: nil, user: user) }

      it "returns enabled smart playlists that need evaluation" do
        expect(described_class.needs_evaluation).to contain_exactly(never_evaluated, stale)
        expect(described_class.needs_evaluation).not_to include(recent, disabled)
      end
    end
  end
end
