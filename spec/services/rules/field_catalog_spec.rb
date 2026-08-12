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

    it "offers presence operators only for the fields a track can lack" do
      offering = described_class.field_keys.select { |key| described_class.supports?(key, "is_not_set") }

      expect(offering).to eq(%w[genre artist])
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

  describe ".constraints_for" do
    it "bounds a number field to what the data can hold" do
      expect(described_class.constraints_for("popularity")).to eq(min: 0, max: 100)
    end

    it "caps the length of a text field" do
      expect(described_class.constraints_for("genre"))
        .to eq(max_length: described_class::MAX_STRING_LENGTH)
    end

    it "returns no limits for a field that needs none" do
      expect(described_class.constraints_for("explicit")).to be_empty
    end

    it "returns no limits for a field it does not know" do
      expect(described_class.constraints_for("bpm")).to be_empty
    end
  end

  describe ".to_h" do
    subject(:payload) { described_class.to_h }

    it "carries the limits the builder enforces" do
      expect(payload).to include(
        max_depth: described_class::MAX_DEPTH,
        max_nodes: described_class::MAX_NODES,
        max_string_length: described_class::MAX_STRING_LENGTH,
        max_list_size: described_class::MAX_LIST_SIZE,
        match_types: %w[all any],
        relative_units: described_class::RELATIVE_UNITS,
      )
    end

    it "serves each field's value constraints so the inputs can mirror them" do
      year = payload[:fields].find { |field| field[:key] == "year" }

      expect(year[:constraints]).to eq(min: 1900, max: 2100)
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

    it "serves a stable shape for every field" do
      expect(payload[:fields].map { |field| field.slice(:key, :value_type, :suggest) }).to eq(
        [
          { key: "genre", value_type: "text", suggest: "genres" },
          { key: "artist", value_type: "text", suggest: "artists" },
          { key: "album", value_type: "text", suggest: "albums" },
          { key: "title", value_type: "text", suggest: nil },
          { key: "year", value_type: "number", suggest: nil },
          { key: "duration", value_type: "duration", suggest: nil },
          { key: "popularity", value_type: "number", suggest: nil },
          { key: "explicit", value_type: "boolean", suggest: nil },
          { key: "date_added", value_type: "date", suggest: nil },
          { key: "playlist", value_type: "playlist", suggest: "playlists" },
        ],
      )
    end

    it "gives every field a constraints key, even when empty" do
      expect(payload[:fields]).to all(include(:constraints))
    end
  end
end
