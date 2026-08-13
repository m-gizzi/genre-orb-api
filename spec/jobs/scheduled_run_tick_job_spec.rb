# frozen_string_literal: true

require "rails_helper"

RSpec.describe ScheduledRunTickJob do
  it "delegates the tick to the supervisor" do
    supervisor = instance_spy(ScheduledRuns::Supervisor)
    allow(ScheduledRuns::Supervisor).to receive(:new).and_return(supervisor)

    described_class.perform_now

    expect(supervisor).to have_received(:call)
  end

  # A tick that raised would take the whole chain down with it; the next one is
  # two minutes away.
  it "swallows and logs an error rather than letting it escape" do
    allow(ScheduledRuns::Supervisor).to receive(:new).and_raise(StandardError, "splat")
    allow(Rails.logger).to receive(:error)

    expect { described_class.perform_now }.not_to raise_error
    expect(Rails.logger).to have_received(:error).with(/splat/)
  end
end
