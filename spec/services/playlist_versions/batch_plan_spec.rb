# frozen_string_literal: true

require "rails_helper"

RSpec.describe PlaylistVersions::BatchPlan do
  def plan(candidates)
    described_class.new(candidates).call
  end

  it "returns nothing for no candidates" do
    expect(plan([])).to be_empty
  end

  it "keeps small versions in one batch" do
    expect(plan([[1, 0], [2, 0], [3, 0]])).to eq([[1, 2, 3]])
  end

  it "preserves the order it was given" do
    expect(plan([[3, 0], [1, 0], [2, 0]])).to eq([[3, 1, 2]])
  end

  describe "the track ceiling" do
    before { stub_const("#{described_class}::TRACK_BUDGET", 10) }

    it "starts a new batch rather than exceeding the budget" do
      expect(plan([[1, 6], [2, 6]])).to eq([[1], [2]])
    end

    it "fills a batch up to the budget" do
      expect(plan([[1, 6], [2, 4], [3, 1]])).to eq([[1, 2], [3]])
    end

    it "gives a version bigger than the whole budget a batch of its own" do
      expect(plan([[1, 99], [2, 1]])).to eq([[1], [2]])
    end

    it "does not strand an oversized version at the end" do
      expect(plan([[1, 1], [2, 99]])).to eq([[1], [2]])
    end

    it "counts rows, not versions" do
      expect(plan([[1, 10], [2, 10], [3, 10]])).to eq([[1], [2], [3]])
    end
  end

  describe "the version ceiling" do
    before { stub_const("#{described_class}::VERSION_BATCH", 2) }

    it "caps a batch of versions that carry no rows at all" do
      expect(plan([[1, 0], [2, 0], [3, 0], [4, 0], [5, 0]])).to eq([[1, 2], [3, 4], [5]])
    end

    it "binds before the track budget when it is the tighter of the two" do
      expect(plan([[1, 1], [2, 1], [3, 1]])).to eq([[1, 2], [3]])
    end
  end
end
