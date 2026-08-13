# frozen_string_literal: true

require "rails_helper"

RSpec.describe Enrichment::Pacer do
  it "does not sleep on the first call" do
    pacer = described_class.new(1.0)
    allow(pacer).to receive(:sleep)

    pacer.wait

    expect(pacer).not_to have_received(:sleep)
  end

  it "sleeps out the remainder of the interval on the next call" do
    pacer = described_class.new(1.0)
    allow(pacer).to receive(:sleep)

    pacer.wait
    pacer.wait

    expect(pacer).to have_received(:sleep).with(a_value_between(0.5, 1.0))
  end

  it "does not sleep when enough time has already passed" do
    pacer = described_class.new(0.01)
    allow(pacer).to receive(:sleep)

    pacer.wait
    Kernel.sleep(0.02)
    pacer.wait

    expect(pacer).not_to have_received(:sleep)
  end

  # A zero interval is how specs inject a no-op pacer, so it must never sleep.
  it "never sleeps with a zero interval" do
    pacer = described_class.new(0)
    allow(pacer).to receive(:sleep)

    3.times { pacer.wait }

    expect(pacer).not_to have_received(:sleep)
  end
end
