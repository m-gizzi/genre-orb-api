# frozen_string_literal: true

require "rails_helper"

RSpec.describe Artists::Filter do
  let(:user) { create(:user) }

  describe "metadata sorts" do
    it "sorts by popularity descending" do
      low = create(:artist, :in_library, user: user, metadata: { "popularity" => 30 })
      high = create(:artist, :in_library, user: user, metadata: { "popularity" => 90 })

      relation = described_class.new(user, { sort: "popularity", order: "desc" }).call

      expect(relation.to_a).to eq([high, low])
    end

    it "treats a non-integer metadata value as unknown instead of failing the query" do
      create(:artist, :in_library, user: user, name: "Malformed", metadata: { "popularity" => "high" })
      good = create(:artist, :in_library, user: user, name: "Good", metadata: { "popularity" => 90 })

      relation = described_class.new(user, { sort: "popularity", order: "desc" }).call

      expect(relation.first).to eq(good)
      expect(relation.count).to eq(2)
    end

    it "treats a missing metadata value as unknown" do
      create(:artist, :in_library, user: user, name: "Unfetched", metadata: {})

      relation = described_class.new(user, { sort: "followers", order: "desc" }).call

      expect(relation.count).to eq(1)
    end
  end
end
