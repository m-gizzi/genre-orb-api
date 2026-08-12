# frozen_string_literal: true

require "rails_helper"

RSpec.describe SmartPlaylists::PushDiff do
  def diff(desired:, current:)
    described_class.new(desired: desired, current: current)
  end

  it "removes what the rules no longer match and adds what is missing" do
    result = diff(desired: %w[a c], current: %w[a b])

    expect(result.to_remove).to eq(%w[b])
    expect(result.to_add).to eq(%w[c])
  end

  it "asks for nothing when the playlist already matches" do
    result = diff(desired: %w[a b], current: %w[b a])

    expect(result.to_remove).to be_empty
    expect(result.to_add).to be_empty
  end

  it "deletes a duplicated track wholesale and re-adds it once" do
    result = diff(desired: %w[a c], current: %w[a a b])

    expect(result.to_remove).to contain_exactly("a", "b")
    expect(result.to_add).to eq(%w[a c])
  end

  it "preserves canonical order in the additions" do
    result = diff(desired: %w[c b a], current: [])

    expect(result.to_add).to eq(%w[c b a])
  end

  it "clears everything when the rules match nothing new" do
    result = diff(desired: [], current: %w[a b])

    expect(result.to_remove).to contain_exactly("a", "b")
    expect(result.to_add).to be_empty
  end

  it "adds everything to an empty playlist" do
    result = diff(desired: %w[a b], current: [])

    expect(result.to_remove).to be_empty
    expect(result.to_add).to eq(%w[a b])
  end
end
