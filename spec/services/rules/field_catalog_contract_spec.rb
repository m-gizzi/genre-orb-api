# frozen_string_literal: true

require "rails_helper"

RSpec.describe Rules::FieldCatalog do
  describe "the contract the builder UI is written against" do
    let(:fixture) { Rails.root.join("spec/fixtures/files/rule_schema.json") }

    it "serves the payload the fixture records" do
      served = JSON.parse(described_class.to_h.to_json)

      expect(served).to eq(JSON.parse(fixture.read)), <<~MESSAGE
        The rule schema changed. Anything the builder UI derives from it —
        widgets, operator labels, value bounds — may no longer match.

        Regenerate this fixture:
          bin/rails rules:schema > spec/fixtures/files/rule_schema.json

        Then mirror the same payload into the web app:
          genre_orb_web/src/test/ruleSchema.ts
      MESSAGE
    end
  end
end
