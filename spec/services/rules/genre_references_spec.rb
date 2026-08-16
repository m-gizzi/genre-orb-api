# frozen_string_literal: true

require "rails_helper"

RSpec.describe Rules::GenreReferences do
  def condition(operator, value)
    { "field" => "genre", "operator" => operator, "value" => value }
  end

  def group(*rules, match: "all")
    { "match" => match, "rules" => rules }
  end

  # Wraps its arguments in a group, since that is the shape a stored rule set always has.
  def extract(*rules, match: "all")
    described_class.extract(group(*rules, match: match))
  end

  describe "exact operators" do
    it "collects an equals value" do
      expect(extract(condition("equals", "metal")).names).to contain_exactly("metal")
    end

    it "collects every value of an in list" do
      expect(extract(condition("in", %w[metal rock])).names)
        .to contain_exactly("metal", "rock")
    end

    it "collects negated operators too — the rule still names the genre" do
      result = extract(condition("not_equals", "metal"), condition("not_in", ["rock"]))

      expect(result.names).to contain_exactly("metal", "rock")
    end

    # The compiler normalizes on the read path, so collecting the raw string would make the
    # two disagree about the same rule.
    it "normalizes the way stored genre names are normalized" do
      expect(extract(condition("equals", "  Death   Metal ")).names)
        .to contain_exactly("death metal")
    end

    it "deduplicates across rules" do
      result = extract(condition("equals", "metal"), condition("equals", "Metal"))

      expect(result.names).to contain_exactly("metal")
    end
  end

  describe "contains" do
    it "is kept apart from the exact names" do
      result = extract(condition("contains", "metal"), condition("equals", "rock"))

      expect(result.patterns).to contain_exactly("metal")
      expect(result.names).to contain_exactly("rock")
    end
  end

  describe "what it ignores" do
    it "ignores presence operators, which name no genre in particular" do
      expect(extract(condition("is_set", nil), condition("is_not_set", nil))).to be_empty
    end

    it "ignores other fields" do
      expect(extract({ "field" => "artist", "operator" => "equals", "value" => "Gojira" }))
        .to be_empty
    end

    it "ignores a blank value" do
      expect(extract(condition("equals", "   "))).to be_empty
    end

    it "ignores a non-string value" do
      expect(extract(condition("equals", 2020))).to be_empty
    end
  end

  describe "tree walking" do
    it "descends into nested groups" do
      result = extract(
        condition("equals", "metal"),
        group(condition("equals", "rock"), group(condition("equals", "jazz"), match: "any")),
      )

      expect(result.names).to contain_exactly("metal", "rock", "jazz")
    end

    it "handles an empty rule set" do
      expect(extract).to be_empty
    end

    it "handles a bare condition with no group around it" do
      expect(described_class.extract(condition("equals", "metal")).names)
        .to contain_exactly("metal")
    end
  end
end
