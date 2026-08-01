# frozen_string_literal: true

require "rails_helper"

RSpec.describe Filters::Range do
  describe ".bounded" do
    it "builds an inclusive range from two numeric bounds" do
      expect(described_class.bounded("1990", "2010")).to eq(1990..2010)
    end

    it "coerces numeric string bounds to integers" do
      expect(described_class.bounded("1990", "2010").first).to be_a(Integer)
    end

    it "builds an endless range from a minimum only" do
      expect(described_class.bounded("1990", nil)).to eq(1990..)
    end

    it "builds a beginless range from a maximum only" do
      expect(described_class.bounded(nil, "2010")).to eq(..2010)
    end

    it "returns nil when both bounds are blank" do
      expect(described_class.bounded(nil, "")).to be_nil
    end

    it "ignores a non-numeric bound" do
      expect(described_class.bounded("abc", "2010")).to eq(..2010)
    end

    it "returns nil when both bounds are non-numeric" do
      expect(described_class.bounded("abc", "xyz")).to be_nil
    end
  end
end
