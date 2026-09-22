# frozen_string_literal: true

require "rails_helper"

RSpec.describe PlaylistVersionPruneJob do
  let(:pruner) { instance_spy(PlaylistVersions::Pruner) }

  before { allow(PlaylistVersions::Pruner).to receive(:new).and_return(pruner) }

  it "delegates the sweep to the pruner" do
    described_class.perform_now

    expect(pruner).to have_received(:call)
  end

  it "logs what the run removed" do
    allow(Rails.logger).to receive(:info)
    allow(pruner).to receive(:call).and_return("versions=7")

    described_class.perform_now

    expect(Rails.logger).to have_received(:info).with(/versions=7/)
  end

  it "swallows and logs an error rather than piling into the retry set" do
    allow(PlaylistVersions::Pruner).to receive(:new).and_raise(StandardError, "splat")
    allow(Rails.logger).to receive(:error)

    expect { described_class.perform_now }.not_to raise_error
    expect(Rails.logger).to have_received(:error).with(/splat/)
  end

  it "does not retry" do
    expect(described_class.sidekiq_options["retry"]).to be(false)
  end

  it "runs on the default queue" do
    expect(described_class.new.queue_name).to eq("default")
  end
end
