# frozen_string_literal: true

require "rails_helper"

RSpec.describe Rules::ValueValidator do
  def errors_for(value, field:, operator:)
    described_class.call(value, field: field, operator: operator)
  end

  describe "arity :one" do
    it "accepts a well-typed scalar" do
      expect(errors_for("rock", field: "genre", operator: "equals")).to be_empty
    end

    it "rejects a value that is not a scalar at all" do
      expect(errors_for(%w[a b], field: "genre", operator: "equals"))
        .to eq(["must have a single value"])
    end

    it "passes the scalar on for type checking" do
      expect(errors_for(42, field: "genre", operator: "equals")).to eq(["must be text"])
    end
  end

  describe "arity :two" do
    it "accepts two well-typed bounds in order" do
      expect(errors_for([2020, 2024], field: "year", operator: "between")).to be_empty
    end

    it "accepts equal bounds" do
      expect(errors_for([2020, 2020], field: "year", operator: "between")).to be_empty
    end

    it "rejects the wrong number of bounds" do
      expect(errors_for([2020], field: "year", operator: "between"))
        .to eq(["must have exactly two values when comparing a range"])
    end

    it "rejects bounds the wrong way round" do
      expect(errors_for([2024, 2020], field: "year", operator: "between"))
        .to eq(["must not have a lower bound greater than its upper bound"])
    end

    it "orders ISO dates correctly" do
      expect(errors_for(%w[2024-06-01 2024-01-01], field: "date_added", operator: "between"))
        .to eq(["must not have a lower bound greater than its upper bound"])
    end

    it "reports a shared typing failure once rather than per bound" do
      expect(errors_for(%w[a b], field: "year", operator: "between"))
        .to eq(["must be a whole number"])
    end

    it "does not compare bounds it could not type" do
      expect(errors_for(["a", 2020], field: "year", operator: "between"))
        .to eq(["must be a whole number"])
    end

    it "rejects a bound that is not a single value" do
      expect(errors_for([2020, nil], field: "year", operator: "between"))
        .to eq(["must contain only single values"])
      expect(errors_for([2020, [2024]], field: "year", operator: "between"))
        .to eq(["must contain only single values"])
    end

    it "reports bounds it cannot order rather than raising" do
      expect(errors_for([true, false], field: "explicit", operator: "between"))
        .to eq(["must have two bounds of the same kind"])
    end
  end

  describe "arity :many" do
    it "accepts a non-empty list of well-typed values" do
      expect(errors_for(%w[Gojira Meshuggah], field: "artist", operator: "in")).to be_empty
    end

    it "rejects an empty list" do
      expect(errors_for([], field: "artist", operator: "in"))
        .to eq(["must have at least one value when matching a list"])
    end

    it "rejects a scalar" do
      expect(errors_for("Gojira", field: "artist", operator: "in"))
        .to eq(["must have at least one value when matching a list"])
    end

    it "rejects a list past the size cap" do
      max = Rules::FieldCatalog::MAX_LIST_SIZE
      values = Array.new(max + 1) { |index| "Artist #{index}" }

      expect(errors_for(values, field: "artist", operator: "in"))
        .to eq(["cannot match more than #{max} values at once"])
    end

    it "accepts a list exactly at the cap" do
      values = Array.new(Rules::FieldCatalog::MAX_LIST_SIZE) { |index| "Artist #{index}" }

      expect(errors_for(values, field: "artist", operator: "in")).to be_empty
    end

    it "type-checks every entry" do
      expect(errors_for(["Gojira", 7], field: "artist", operator: "in")).to eq(["must be text"])
    end

    it "rejects an entry that is not a single value, rather than calling the list empty" do
      expect(errors_for(["Gojira", nil], field: "artist", operator: "in"))
        .to eq(["must contain only single values"])
      expect(errors_for([nil], field: "artist", operator: "in"))
        .to eq(["must contain only single values"])
    end
  end

  describe "arity :relative" do
    it "accepts a count and a known unit" do
      expect(errors_for({ "count" => 30, "unit" => "days" },
                        field: "date_added", operator: "in_the_last",)).to be_empty
    end

    it "rejects a non-hash" do
      expect(errors_for(30, field: "date_added", operator: "in_the_last"))
        .to eq(["must have a count and a unit"])
    end

    it "rejects a non-positive count" do
      expect(errors_for({ "count" => 0, "unit" => "days" },
                        field: "date_added", operator: "in_the_last",))
        .to eq(["must have a whole number count"])
    end

    it "rejects an unknown unit" do
      units = Rules::FieldCatalog::RELATIVE_UNITS.join(", ")

      expect(errors_for({ "count" => 30, "unit" => "fortnights" },
                        field: "date_added", operator: "in_the_last",))
        .to eq(["must use one of these units: #{units}"])
    end

    it "reports both halves when both are wrong" do
      expect(errors_for({ "count" => -1, "unit" => "fortnights" },
                        field: "date_added", operator: "in_the_last",).size).to eq(2)
    end

    it "rejects keys it does not recognise" do
      expect(errors_for({ "count" => 30, "unit" => "days", "junk" => 1 },
                        field: "date_added", operator: "in_the_last",))
        .to eq(['has unexpected keys: "junk"'])
    end
  end

  it "has no opinion on an operator with no arity" do
    expect(errors_for("x", field: "genre", operator: "matches_sql")).to be_empty
  end
end
