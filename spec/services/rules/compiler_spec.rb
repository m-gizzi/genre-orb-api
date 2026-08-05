# frozen_string_literal: true

require "rails_helper"

RSpec.describe Rules::Compiler do
  subject(:compiler) { described_class.new(memberships) }

  let(:memberships) do
    PlaylistVersionTrack.where(playlist_version_id: [1]).group(:track_id).select("track_id, MIN(added_at) AS added_at")
  end

  def condition(value)
    { "field" => "genre", "operator" => "equals", "value" => value }
  end

  def group(match, *rules, **extra)
    { "match" => match, "rules" => rules, **extra }
  end

  def sql_for(node)
    compiler.call(node).to_sql
  end

  describe "a bare condition" do
    it "compiles without a group around it" do
      expect(sql_for(condition("metal"))).to start_with('"tracks"."id" IN')
    end
  end

  describe "combining children" do
    it "intersects the children of an all group" do
      sql = sql_for(group("all", condition("metal"), condition("rock")))

      expect(sql).to include(" AND ")
      expect(sql).not_to include(" OR ")
    end

    it "unions the children of an any group" do
      sql = sql_for(group("any", condition("metal"), condition("rock")))

      expect(sql).to include(" OR ")
      expect(sql).not_to include(" AND ")
    end

    it "groups the junction so it cannot be re-associated by an outer one" do
      expect(sql_for(group("any", condition("metal"), condition("rock")))).to start_with("(").and end_with(")")
    end

    it "passes a lone child through without a junction, whatever the match" do
      bare = sql_for(condition("metal"))

      expect(sql_for(group("all", condition("metal")))).to eq(bare)
      expect(sql_for(group("any", condition("metal")))).to eq(bare)
    end
  end

  describe "an empty group" do
    it "matches the whole pool for all, so an unfinished rule set does not hide it" do
      expect(sql_for(group("all"))).to eq("TRUE")
    end

    it "matches nothing for any" do
      expect(sql_for(group("any"))).to eq("FALSE")
    end
  end

  describe "negation" do
    it "wraps the group's predicate in NOT" do
      expect(sql_for(group("any", condition("metal"), "not" => true))).to start_with("NOT (")
    end

    it "negates the whole junction rather than the first child" do
      sql = sql_for(group("any", condition("metal"), condition("rock"), "not" => true))

      expect(sql).to eq("NOT (#{sql_for(group("any", condition("metal"), condition("rock")))})")
    end

    it "leaves a group alone when not is false" do
      expect(sql_for(group("any", condition("metal"), "not" => false))).not_to include("NOT (")
    end

    it "inverts an empty all group, which is how NOT of everything reads" do
      sql = sql_for(group("all", "not" => true))

      expect(sql).to start_with("NOT (")
      expect(sql).to include("TRUE")
    end
  end

  describe "nesting" do
    it "compiles a group inside a group" do
      nested = group("all", condition("metal"), group("any", condition("rock"), condition("punk")))

      expect(sql_for(nested)).to include(" AND ").and include(" OR ")
    end
  end
end
