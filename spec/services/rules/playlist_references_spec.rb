# frozen_string_literal: true

require "rails_helper"

RSpec.describe Rules::PlaylistReferences do
  def condition(field, value)
    { "field" => field, "operator" => "not_in", "value" => value }
  end

  describe ".extract" do
    it "finds ids on a playlist condition" do
      rules = { "match" => "all", "rules" => [condition("playlist", [7, 9])] }

      expect(described_class.extract(rules)).to eq([7, 9])
    end

    it "ignores conditions on other fields" do
      rules = { "match" => "all", "rules" => [condition("genre", %w[rock metal])] }

      expect(described_class.extract(rules)).to be_empty
    end

    it "reaches into nested groups" do
      rules = {
        "match" => "all",
        "rules" => [
          condition("playlist", [1]),
          { "match" => "any", "not" => true,
            "rules" => [{ "match" => "all", "rules" => [condition("playlist", [2])] }], },
        ],
      }

      expect(described_class.extract(rules)).to contain_exactly(1, 2)
    end

    it "reports an id once however many rules name it" do
      rules = { "match" => "all", "rules" => [condition("playlist", [3]), condition("playlist", [3, 4])] }

      expect(described_class.extract(rules)).to contain_exactly(3, 4)
    end

    it "is empty for a rule set with no rules" do
      expect(described_class.extract(SmartPlaylist::EMPTY_RULES)).to be_empty
    end

    it "keeps only whole numbers, whatever else a stored tree holds" do
      rules = { "match" => "all", "rules" => [condition("playlist", ["7", nil, 9])] }

      expect(described_class.extract(rules)).to eq([9])
    end
  end
end
