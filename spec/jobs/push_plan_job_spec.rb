# frozen_string_literal: true

require "rails_helper"

RSpec.describe PushPlanJob do
  let(:user) { create(:user) }
  let(:target) { create(:playlist, :with_spotify, user: user) }
  let(:smart_playlist) { create(:smart_playlist, :with_rules, target_playlist: target) }
  let(:session) { create(:push_session, :running, smart_playlist: smart_playlist) }
  let(:planner) { instance_spy(SmartPlaylists::PushPlanner) }

  before do
    create(:service_connection, user: user)
    allow(SmartPlaylists::PushPlanner).to receive(:new).and_return(planner)
  end

  def run
    described_class.perform_now(push_session_id: session.id)
    session.reload
  end

  context "when the rule set outruns the planner's statement timeout" do
    before { allow(planner).to receive(:call).and_raise(ActiveRecord::QueryCanceled) }

    it "fails the session with the evaluation timeout copy" do
      run

      expect(session).to be_failed
      expect(session.error_message).to eq(I18n.t("api.smart_playlists.evaluation_timeout"))
    end

    it "does not re-raise, so Sidekiq stops retrying a deterministically slow rule set" do
      expect { run }.not_to raise_error
    end
  end

  it "does not plan for a session that has already gone terminal" do
    session.update!(status: :failed)

    run

    expect(planner).not_to have_received(:call)
  end
end
