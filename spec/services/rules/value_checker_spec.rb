# frozen_string_literal: true

require "rails_helper"

RSpec.describe Rules::ValueChecker do
  describe ".error_for" do
    context "with a text field" do
      it "accepts a string" do
        expect(described_class.error_for("genre", "death metal")).to be_nil
      end

      it "rejects a non-string" do
        expect(described_class.error_for("genre", 42)).to eq("must be text")
        expect(described_class.error_for("genre", true)).to eq("must be text")
      end

      it "rejects a string that is blank once stripped" do
        expect(described_class.error_for("genre", "")).to eq("must not be blank")
        expect(described_class.error_for("genre", "   ")).to eq("must not be blank")
      end

      it "rejects a string past the length cap" do
        long = "a" * (Rules::FieldCatalog::MAX_STRING_LENGTH + 1)

        expect(described_class.error_for("title", long))
          .to eq("must be #{Rules::FieldCatalog::MAX_STRING_LENGTH} characters or fewer")
      end

      it "accepts a string exactly at the cap" do
        at_cap = "a" * Rules::FieldCatalog::MAX_STRING_LENGTH

        expect(described_class.error_for("title", at_cap)).to be_nil
      end
    end

    context "with a number field" do
      it "accepts an integer inside the range" do
        expect(described_class.error_for("year", 2020)).to be_nil
        expect(described_class.error_for("popularity", 0)).to be_nil
        expect(described_class.error_for("popularity", 100)).to be_nil
      end

      it "rejects a non-integer" do
        expect(described_class.error_for("year", "2020")).to eq("must be a whole number")
        expect(described_class.error_for("year", 2020.5)).to eq("must be a whole number")
      end

      it "rejects a value outside the range" do
        expect(described_class.error_for("popularity", 101)).to eq("must be between 0 and 100")
        expect(described_class.error_for("year", 1899)).to eq("must be between 1900 and 2100")
      end
    end

    context "with a duration field" do
      it "accepts milliseconds inside the range" do
        expect(described_class.error_for("duration", 210_000)).to be_nil
      end

      it "rejects a negative duration" do
        expect(described_class.error_for("duration", -1)).to eq("must be between 0 and 86400000")
      end
    end

    context "with a boolean field" do
      it "accepts true and false" do
        expect(described_class.error_for("explicit", true)).to be_nil
        expect(described_class.error_for("explicit", false)).to be_nil
      end

      it "rejects anything else" do
        expect(described_class.error_for("explicit", "true")).to eq("must be true or false")
        expect(described_class.error_for("explicit", 1)).to eq("must be true or false")
      end
    end

    context "with a date field" do
      it "accepts an ISO 8601 date" do
        expect(described_class.error_for("date_added", "2024-01-15")).to be_nil
      end

      it "rejects another date format" do
        expect(described_class.error_for("date_added", "15/01/2024"))
          .to eq("must be a date in YYYY-MM-DD form")
      end

      it "rejects a well-formed date that does not exist" do
        expect(described_class.error_for("date_added", "2024-02-31"))
          .to eq("must be a date in YYYY-MM-DD form")
      end

      it "rejects a timestamp" do
        expect(described_class.error_for("date_added", "2024-01-15T09:00:00Z"))
          .to eq("must be a date in YYYY-MM-DD form")
      end
    end

    context "with a playlist field" do
      it "accepts a record id" do
        expect(described_class.error_for("playlist", 42)).to be_nil
      end

      it "rejects an id that could not name a record" do
        expect(described_class.error_for("playlist", 0)).to eq("must refer to a playlist")
        expect(described_class.error_for("playlist", -1)).to eq("must refer to a playlist")
      end

      it "rejects anything that is not a whole number" do
        expect(described_class.error_for("playlist", "42")).to eq("must refer to a playlist")
        expect(described_class.error_for("playlist", 4.2)).to eq("must refer to a playlist")
      end
    end

    it "has no opinion on a field it does not know" do
      expect(described_class.error_for("bpm", "anything")).to be_nil
    end
  end
end
