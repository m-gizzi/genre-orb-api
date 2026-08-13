# frozen_string_literal: true

require "rails_helper"

RSpec.describe ScheduledRuns::Supervisor do
  def inside_window
    Time.utc(2026, 8, 13, ScheduledRun::RUN_HOUR, 30, 0)
  end

  def outside_window
    Time.utc(2026, 8, 13, ScheduledRun::RUN_HOUR + ScheduledRun::KICKOFF_WINDOW.in_hours.to_i + 1, 0, 0)
  end

  it "starts a run inside the kickoff window" do
    travel_to(inside_window) do
      expect { described_class.new.call }.to change(ScheduledRun, :count).by(1)
    end
  end

  it "skips the night entirely once the window has closed" do
    travel_to(outside_window) do
      expect { described_class.new.call }.not_to change(ScheduledRun, :count)
    end
  end

  it "does not start a second run for a day that already has one" do
    travel_to(inside_window) do
      create(:scheduled_run, :completed, run_date: Date.current)

      expect { described_class.new.call }.not_to change(ScheduledRun, :count)
    end
  end

  it "advances the run in flight instead of starting one" do
    run = create(:scheduled_run, run_date: Date.current - 1)
    advancer = instance_spy(ScheduledRuns::Advancer)
    allow(ScheduledRuns::Advancer).to receive(:new).with(run).and_return(advancer)

    travel_to(inside_window) { described_class.new.call }

    expect(advancer).to have_received(:call)
  end
end
