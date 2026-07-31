# frozen_string_literal: true

require "rails_helper"

RSpec.describe Albums::Filter do
  let(:user) { create(:user) }

  describe "popularity sort" do
    it "orders by average track popularity" do
      popular = create(:album, title: "Popular")
      create(:track, :in_library, user: user, album: popular, popularity: 90)
      niche = create(:album, title: "Niche")
      create(:track, :in_library, user: user, album: niche, popularity: 10)

      relation = described_class.new(user, { sort: "popularity", order: "desc" }).call

      expect(relation.to_a).to eq([popular, niche])
    end

    it "answers a plain #count, not only count(:all)" do
      create(:track, :in_library, user: user, album: create(:album), popularity: 50)

      relation = described_class.new(user, { sort: "popularity" }).call

      expect(relation.count).to eq(1)
      expect(relation.count(:all)).to eq(1)
    end
  end
end
