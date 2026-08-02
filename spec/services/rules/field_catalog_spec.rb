# frozen_string_literal: true

require "rails_helper"

RSpec.describe Rules::FieldCatalog do
  describe ".field?" do
    it "knows the catalogued fields" do
      expect(described_class).to be_field("genre")
      expect(described_class).to be_field("popularity")
    end

    it "does not know fields without a data source" do
      expect(described_class).not_to be_field("play_count")
      expect(described_class).not_to be_field("last_played")
    end
  end

  describe ".supports?" do
    it "allows operators the field lists" do
      expect(described_class).to be_supports("genre", "in")
      expect(described_class).to be_supports("date_added", "in_the_last")
    end

    it "rejects operators from another field's vocabulary" do
      expect(described_class).not_to be_supports("genre", "greater_than")
      expect(described_class).not_to be_supports("duration", "contains")
    end
  end

  describe ".arity" do
    it "maps each operator to a value shape" do
      expect(described_class.arity("equals")).to eq(:one)
      expect(described_class.arity("between")).to eq(:two)
      expect(described_class.arity("not_in")).to eq(:many)
      expect(described_class.arity("in_the_last")).to eq(:relative)
    end
  end

  describe ".to_h" do
    subject(:payload) { described_class.to_h }

    it "carries the limits the builder enforces" do
      expect(payload).to include(
        max_depth: described_class::MAX_DEPTH,
        max_nodes: described_class::MAX_NODES,
        match_types: %w[all any],
        relative_units: described_class::RELATIVE_UNITS,
      )
    end

    it "describes every operator's arity" do
      expect(payload[:operators].keys).to match_array(described_class::OPERATORS.keys)
      expect(payload[:operators]["in"]).to eq(arity: :many)
    end

    it "serializes fields with labelled operators" do
      genre = payload[:fields].find { |field| field[:key] == "genre" }

      expect(genre).to include(key: "genre", label: "Genre", value_type: "text", suggest: "genres")
      expect(genre[:operators]).to include(key: "equals", label: "is")
      expect(genre[:operators]).to include(key: "in", label: "is any of")
    end

    it "only advertises operators the validator accepts" do
      payload[:fields].each do |field|
        field[:operators].each do |operator|
          expect(described_class).to be_supports(field[:key], operator[:key])
        end
      end
    end
  end
end
