# frozen_string_literal: true

require "rails_helper"

RSpec.describe ScheduledRuns::Starter do
  let!(:user) do
    create(:user).tap do |record|
      create(:service_connection, user: record)
      create(:playlist, :with_spotify, :sync_enabled, user: record)
    end
  end

  it "creates today's run in the discovery stage and starts it" do
    run = described_class.new.call

    expect(run).to have_attributes(run_date: Date.current, status: "running", stage: "discovery")
    expect(run.stage_total).to eq(1)
  end

  it "enqueues one discovery job per eligible user" do
    expect { described_class.new.call }
      .to have_enqueued_job(ScheduledPlaylistDiscoveryJob).with(hash_including(user_id: user.id))
  end

  it "does not start a second run the same day" do
    described_class.new.call.update!(status: :completed, completed_at: Time.current)

    expect { described_class.new.call }.not_to change(ScheduledRun, :count)
  end

  it "returns nil rather than raising when a run is already active" do
    create(:scheduled_run, run_date: Date.current - 1)

    expect(described_class.new.call).to be_nil
  end
end
