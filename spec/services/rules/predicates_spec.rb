# frozen_string_literal: true

require "rails_helper"

RSpec.describe Rules::Predicates do
  def sql_for(field, operator, value)
    condition = Rules::Condition.new({ "field" => field, "operator" => operator, "value" => value })
    described_class.call(condition, Track.arel_table[:title]).to_sql
  end

  def numeric_sql(operator, value)
    condition = Rules::Condition.new({ "field" => "year", "operator" => operator, "value" => value })
    described_class.call(condition, Album.arel_table[:release_year]).to_sql
  end

  def date_sql(operator, value)
    condition = Rules::Condition.new({ "field" => "date_added", "operator" => operator, "value" => value })
    described_class.call(condition, PlaylistVersionTrack.arel_table[:added_at]).to_sql
  end

  describe "text" do
    it "matches case-insensitively so user-typed values find stored casing" do
      expect(sql_for("title", "equals", "gojira")).to eq(%q("tracks"."title" ILIKE 'gojira'))
    end

    it "anchors contains, starts_with and ends_with with wildcards" do
      expect(sql_for("title", "contains", "war")).to include("ILIKE '%war%'")
      expect(sql_for("title", "starts_with", "war")).to include("ILIKE 'war%'")
      expect(sql_for("title", "ends_with", "war")).to include("ILIKE '%war'")
    end

    it "escapes LIKE metacharacters in the value" do
      expect(sql_for("title", "contains", "50%_off")).to include(%q(ILIKE '%50\%\_off%'))
    end

    it "ors the entries of a list" do
      sql = sql_for("title", "in", %w[one two])

      expect(sql).to eq(%q(("tracks"."title" ILIKE 'one' OR "tracks"."title" ILIKE 'two')))
    end

    it "reads a negated operator as its positive twin" do
      expect(sql_for("title", "not_equals", "war")).to eq(sql_for("title", "equals", "war"))
    end
  end

  describe "numbers" do
    it "treats greater_than and less_than as strict" do
      expect(numeric_sql("greater_than", 2020)).to include("> 2020")
      expect(numeric_sql("less_than", 2020)).to include("< 2020")
    end

    it "treats between as inclusive of both bounds" do
      expect(numeric_sql("between", [2020, 2024])).to include("BETWEEN 2020 AND 2024")
    end
  end

  describe "dates" do
    it "starts greater_than at the midnight after the named day" do
      expect(date_sql("greater_than", "2024-01-01")).to include("'2024-01-02 00:00:00'")
    end

    it "ends less_than at the midnight of the named day" do
      sql = date_sql("less_than", "2024-01-01")

      expect(sql).to include("< '2024-01-01 00:00:00'")
    end

    it "covers both whole days for between" do
      sql = date_sql("between", %w[2024-01-01 2024-06-30])

      expect(sql).to include(">= '2024-01-01 00:00:00'").and include("< '2024-07-01 00:00:00'")
    end

    it "measures in_the_last back from now" do
      freeze_time do
        sql = date_sql("in_the_last", { "count" => 30, "unit" => "days" })

        expect(sql).to include(">= '#{30.days.ago.utc.strftime("%Y-%m-%d %H:%M:%S")}")
      end
    end

    it "refuses a relative unit the catalog does not declare" do
      expect { date_sql("in_the_last", { "count" => 1, "unit" => "fortnights" }) }
        .to raise_error(ArgumentError, /unsupported relative unit/)
    end

    it "refuses an operator it has no branch for" do
      expect { date_sql("equals", "2024-01-01") }
        .to raise_error(ArgumentError, /unsupported date operator/)
    end
  end

  describe "booleans" do
    it "compares directly" do
      condition = Rules::Condition.new({ "field" => "explicit", "operator" => "equals", "value" => false })

      sql = described_class.call(condition, Track.arel_table[:explicit]).to_sql

      expect(sql).to eq('"tracks"."explicit" = FALSE')
    end
  end
end
