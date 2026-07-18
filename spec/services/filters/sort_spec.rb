# frozen_string_literal: true

require "rails_helper"

RSpec.describe Filters::Sort do
  let(:nodes) do
    {
      "name" => -> { Genre.arel_table[:name] },
      "id" => -> { Genre.arel_table[:id] },
    }
  end

  def order_sql(params, nulls: :none, extra: [])
    sort = described_class.new(nodes: nodes, params: params, default: "name", nulls: nulls)
    Genre.order(*sort.terms(*extra)).to_sql
  end

  describe "#key" do
    it "returns the requested sort when whitelisted" do
      sort = described_class.new(nodes: nodes, params: { sort: "id" }, default: "name")
      expect(sort.key).to eq("id")
    end

    it "falls back to the default for unknown or missing sorts" do
      expect(described_class.new(nodes: nodes, params: { sort: "bogus" }, default: "name").key).to eq("name")
      expect(described_class.new(nodes: nodes, params: {}, default: "name").key).to eq("name")
    end
  end

  describe "nulls policies" do
    it ":none applies no NULLS clause in either direction" do
      expect(order_sql({ order: "desc" }, nulls: :none)).not_to include("NULLS")
      expect(order_sql({ order: "asc" }, nulls: :none)).not_to include("NULLS")
    end

    it ":directional puts NULLs last on desc and first on asc" do
      expect(order_sql({ order: "desc" }, nulls: :directional)).to include("DESC NULLS LAST")
      expect(order_sql({ order: "asc" }, nulls: :directional)).to include("ASC NULLS FIRST")
    end

    it ":last puts NULLs last regardless of direction" do
      expect(order_sql({ order: "desc" }, nulls: :last)).to include("DESC NULLS LAST")
      expect(order_sql({ order: "asc" }, nulls: :last)).to include("ASC NULLS LAST")
    end
  end

  it "appends extra tiebreaker terms after the primary sort" do
    sql = order_sql({ order: "asc" }, extra: [Genre.arel_table[:id].asc])
    expect(sql).to match(/ORDER BY.*"genres"\."name" ASC.*"genres"\."id" ASC/)
  end
end
