# frozen_string_literal: true

require "rails_helper"

# A value of the right primitive type and within bounds for each field, one per
# arity. RuleSetValidator guarantees these shapes before the compiler runs.
RULE_VALUES = {
  "text" => { one: "metal", many: %w[metal rock], none: nil },
  "number" => { one: 2020, two: [2020, 2024] },
  "duration" => { one: 120_000, two: [60_000, 300_000] },
  "boolean" => { one: true },
  "date" => { one: "2024-01-01", two: %w[2024-01-01 2024-06-30],
              relative: { "count" => 30, "unit" => "days" }, },
  "playlist" => { many: [1, 2] },
}.freeze

RSpec.describe Rules::ConditionCompiler do
  subject(:compiler) { described_class.new(memberships, user) }

  let(:user) { create(:user) }

  let(:memberships) do
    PlaylistVersionTrack.where(playlist_version_id: [1]).group(:track_id).select("track_id, MIN(added_at) AS added_at")
  end

  def value_for(field, operator)
    arity = Rules::FieldCatalog.arity(operator)
    RULE_VALUES.fetch(Rules::FieldCatalog.value_type_for(field)).fetch(arity)
  end

  describe "catalog coverage" do
    it "handles every field the catalog declares" do
      handled = described_class::SOURCES.keys + [described_class::DATE_ADDED]

      expect(handled).to match_array(Rules::FieldCatalog.field_keys)
    end

    Rules::FieldCatalog.field_keys.each do |field|
      Rules::FieldCatalog.operators_for(field).each do |operator|
        it "compiles #{field} #{operator} to a track-id predicate" do
          node = { "field" => field, "operator" => operator, "value" => value_for(field, operator) }

          sql = compiler.call(node).to_sql

          expect(sql).to start_with('"tracks"."id" ')
          expect(sql).to include("SELECT")
        end
      end
    end
  end

  describe "negation" do
    it "complements the positive set rather than inverting the comparison" do
      positive = compiler.call({ "field" => "artist", "operator" => "equals", "value" => "Gojira" }).to_sql
      negative = compiler.call({ "field" => "artist", "operator" => "not_equals", "value" => "Gojira" }).to_sql

      expect(positive).to start_with('"tracks"."id" IN')
      expect(negative).to start_with('"tracks"."id" NOT IN')
      expect(negative.sub("NOT IN", "IN")).to eq(positive)
    end

    it "complements in with not_in" do
      sql = compiler.call({ "field" => "genre", "operator" => "not_in", "value" => %w[metal rock] }).to_sql

      expect(sql).to start_with('"tracks"."id" NOT IN')
      expect(sql).to include("ILIKE 'metal' OR").and include("ILIKE 'rock'")
    end
  end

  describe "presence operators" do
    it "asks for every track the source has a row for" do
      sql = compiler.call({ "field" => "genre", "operator" => "is_set", "value" => nil }).to_sql

      expect(sql).to start_with('"tracks"."id" IN (SELECT DISTINCT "track_genres"."track_id"')
    end

    it "names each track once however many rows it has" do
      sql = compiler.call({ "field" => "genre", "operator" => "is_not_set", "value" => nil }).to_sql

      expect(sql).to include('SELECT DISTINCT "track_genres"."track_id"')
    end

    it "does not reach the named entity it has no value to compare against" do
      sql = compiler.call({ "field" => "genre", "operator" => "is_set", "value" => nil }).to_sql

      expect(sql).not_to include('INNER JOIN "genres"')
    end

    it "bounds the set by the same pool the outer query draws from" do
      sql = compiler.call({ "field" => "genre", "operator" => "is_set", "value" => nil }).to_sql

      expect(sql).to include('"track_genres"."track_id" IN (SELECT "playlist_version_tracks"."track_id"')
    end

    it "reads is_not_set as having no value at all" do
      positive = compiler.call({ "field" => "genre", "operator" => "is_set", "value" => nil }).to_sql
      negative = compiler.call({ "field" => "genre", "operator" => "is_not_set", "value" => nil }).to_sql

      expect(negative).to start_with('"tracks"."id" NOT IN')
      expect(negative.sub("NOT IN", "IN")).to eq(positive)
    end
  end

  describe "playlist membership" do
    it "counts only each playlist's current version" do
      sql = compiler.call({ "field" => "playlist", "operator" => "in", "value" => [7] }).to_sql

      expect(sql).to include('"playlists"."current_version_id" = "playlist_versions"."id"')
      expect(sql).to include('"playlists"."id" IN (7)')
    end

    it "excludes by complementing the membership set" do
      sql = compiler.call({ "field" => "playlist", "operator" => "not_in", "value" => [7, 9] }).to_sql

      expect(sql).to start_with('"tracks"."id" NOT IN')
      expect(sql).to include('"playlists"."id" IN (7, 9)')
    end
  end

  describe "genre names" do
    it "normalizes the value the way stored genre names are normalized" do
      sql = compiler.call({ "field" => "genre", "operator" => "equals", "value" => "  Death   Metal " }).to_sql

      expect(sql).to include("ILIKE 'death metal'")
    end
  end

  describe "date_added" do
    it "filters the grouped memberships on the earliest add" do
      node = { "field" => "date_added", "operator" => "in_the_last",
               "value" => { "count" => 7, "unit" => "days" }, }

      sql = compiler.call(node).to_sql

      expect(sql).to include('HAVING MIN("playlist_version_tracks"."added_at") >=')
      expect(sql).to include("GROUP BY")
    end
  end
end
