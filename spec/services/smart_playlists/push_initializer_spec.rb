# frozen_string_literal: true

require "rails_helper"

RSpec.describe SmartPlaylists::PushInitializer do
  let(:user) { create(:user) }
  let(:target) { create(:playlist, :with_spotify, user: user) }
  let(:smart_playlist) { create(:smart_playlist, :with_rules, target_playlist: target) }

  def call(record = smart_playlist)
    described_class.new(record).call
  end

  context "when Spotify is connected" do
    before { create(:service_connection, user: user) }

    it "creates a running session and enqueues the planner" do
      result = nil

      expect { result = call }.to have_enqueued_job(PushPlanJob)

      expect(result).to be_started
      expect(result.session).to be_running
      expect(result.session.started_at).to be_present
    end

    it "refuses a smart playlist with no rules" do
      draft = create(:smart_playlist, target_playlist: create(:playlist, :with_spotify, user: user))

      expect(call(draft).outcome).to eq(:not_ready)
    end

    it "refuses while a push for the same smart playlist is already running" do
      create(:push_session, :running, smart_playlist: smart_playlist)

      expect(call.outcome).to eq(:already_in_progress)
    end

    it "allows a new push once the previous one finished" do
      create(:push_session, :completed, smart_playlist: smart_playlist)

      expect(call).to be_started
    end

    it "does not enqueue anything when it refuses" do
      create(:push_session, :running, smart_playlist: smart_playlist)

      expect { call }.not_to have_enqueued_job(PushPlanJob)
    end

    it "translates the unique index into an already-in-progress outcome" do
      allow(PushSession).to receive(:create!).and_raise(ActiveRecord::RecordNotUnique)

      expect(call.outcome).to eq(:already_in_progress)
    end
  end

  it "refuses when Spotify is not connected" do
    expect(call.outcome).to eq(:spotify_not_connected)
  end
end
