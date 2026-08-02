# frozen_string_literal: true

require "rails_helper"

RSpec.describe SmartPlaylist do
  describe "validations" do
    it "requires at least one source playlist" do
      smart_playlist = build(:smart_playlist, source_count: 0)

      expect(smart_playlist).not_to be_valid
      expect(smart_playlist.errors[:source_playlists]).to include("must include at least one playlist")
    end

    it "rejects sources owned by a different user" do
      smart_playlist = build(:smart_playlist, source_count: 0)
      smart_playlist.smart_playlist_sources.build(playlist: create(:playlist))

      expect(smart_playlist).not_to be_valid
      expect(smart_playlist.errors[:source_playlists])
        .to include("must belong to the same user as the target playlist")
    end

    it "allows only one smart playlist per target playlist" do
      existing = create(:smart_playlist)
      duplicate = build(:smart_playlist, target_playlist: existing.target_playlist)

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:target_playlist_id]).to be_present
    end

    it "rejects Liked Songs as a target" do
      user = create(:user)
      smart_playlist = build(:smart_playlist, user: user,
                                              target_playlist: create(:liked_songs_playlist, user: user),)

      expect(smart_playlist).not_to be_valid
      expect(smart_playlist.errors[:target_playlist])
        .to include("must be a playlist that exists on Spotify")
    end

    it "rejects rules without match and rules keys" do
      smart_playlist = build(:smart_playlist, rules: { "foo" => "bar" })

      expect(smart_playlist).not_to be_valid
      expect(smart_playlist.errors[:rules]).to include("must have 'match' and 'rules' keys")
    end

    it "accepts the nested groups the query builder supports" do
      expect(build(:smart_playlist, :complex_rules)).to be_valid
    end

    it "cannot be enabled while the ruleset is empty" do
      smart_playlist = build(:smart_playlist, is_enabled: true)

      expect(smart_playlist).not_to be_valid
      expect(smart_playlist.errors[:is_enabled])
        .to include("cannot be turned on until at least one rule is added")
    end

    it "can be enabled once it has a rule" do
      expect(build(:smart_playlist, :enabled)).to be_valid
    end
  end

  describe "rule set validation" do
    def with_rules(rules)
      build(:smart_playlist, rules: { "match" => "all", "rules" => rules })
    end

    it "rejects an unknown field" do
      smart_playlist = with_rules([{ "field" => "bpm", "operator" => "equals", "value" => "120" }])

      expect(smart_playlist).not_to be_valid
      expect(smart_playlist.errors[:rules]).to include('has an unknown field: "bpm"')
    end

    it "rejects an unknown operator" do
      smart_playlist = with_rules([{ "field" => "genre", "operator" => "matches_sql", "value" => "x" }])

      expect(smart_playlist).not_to be_valid
      expect(smart_playlist.errors[:rules]).to include('has an unknown operator: "matches_sql"')
    end

    it "rejects a rule with no value" do
      smart_playlist = with_rules([{ "field" => "genre", "operator" => "equals" }])

      expect(smart_playlist).not_to be_valid
      expect(smart_playlist.errors[:rules]).to include("each rule must have a value")
    end

    it "accepts a false value" do
      expect(with_rules([{ "field" => "genre", "operator" => "equals", "value" => false }])).to be_valid
    end

    it "rejects a field the catalog dropped" do
      smart_playlist = with_rules([{ "field" => "play_count", "operator" => "greater_than", "value" => 5 }])

      expect(smart_playlist).not_to be_valid
      expect(smart_playlist.errors[:rules]).to include('has an unknown field: "play_count"')
    end

    it "rejects an operator the field does not support" do
      smart_playlist = with_rules([{ "field" => "genre", "operator" => "greater_than", "value" => "rock" }])

      expect(smart_playlist).not_to be_valid
      expect(smart_playlist.errors[:rules])
        .to include('does not support the operator "greater_than" on the field "genre"')
    end

    it "rejects a list operator given a scalar" do
      smart_playlist = with_rules([{ "field" => "artist", "operator" => "in", "value" => "Gojira" }])

      expect(smart_playlist).not_to be_valid
      expect(smart_playlist.errors[:rules]).to include("must have at least one value when matching a list")
    end

    it "accepts a list operator given a list" do
      expect(
        with_rules([{ "field" => "artist", "operator" => "in", "value" => %w[Gojira Meshuggah] }]),
      ).to be_valid
    end

    it "rejects a range operator without exactly two values" do
      smart_playlist = with_rules([{ "field" => "year", "operator" => "between", "value" => [2020] }])

      expect(smart_playlist).not_to be_valid
      expect(smart_playlist.errors[:rules])
        .to include("must have exactly two values when comparing a range")
    end

    it "accepts a range operator given two values" do
      expect(
        with_rules([{ "field" => "year", "operator" => "between", "value" => [2020, 2024] }]),
      ).to be_valid
    end

    it "rejects a scalar operator given a blank value" do
      smart_playlist = with_rules([{ "field" => "title", "operator" => "contains", "value" => "" }])

      expect(smart_playlist).not_to be_valid
      expect(smart_playlist.errors[:rules]).to include("must have a single value")
    end

    it "accepts a relative date value" do
      expect(
        with_rules([
                     { "field" => "date_added", "operator" => "in_the_last",
                       "value" => { "count" => 30, "unit" => "days" }, },
                   ]),
      ).to be_valid
    end

    it "rejects a relative date with an unknown unit" do
      smart_playlist = with_rules([
                                    { "field" => "date_added", "operator" => "in_the_last",
                                      "value" => { "count" => 30, "unit" => "fortnights" }, },
                                  ])

      expect(smart_playlist).not_to be_valid
      expect(smart_playlist.errors[:rules])
        .to include("must use one of these units: #{Rules::FieldCatalog::RELATIVE_UNITS.join(", ")}")
    end

    it "rejects a relative date with a non-positive count" do
      smart_playlist = with_rules([
                                    { "field" => "date_added", "operator" => "in_the_last",
                                      "value" => { "count" => 0, "unit" => "days" }, },
                                  ])

      expect(smart_playlist).not_to be_valid
      expect(smart_playlist.errors[:rules]).to include("must have a whole number count")
    end

    it "accepts the newly catalogued fields" do
      expect(
        with_rules([
                     { "field" => "popularity", "operator" => "greater_than", "value" => 50 },
                     { "field" => "explicit", "operator" => "equals", "value" => false },
                     { "field" => "duration", "operator" => "between", "value" => [120_000, 300_000] },
                   ]),
      ).to be_valid
    end

    it "rejects an unknown match type" do
      smart_playlist = build(:smart_playlist, rules: { "match" => "some", "rules" => [] })

      expect(smart_playlist).not_to be_valid
      expect(smart_playlist.errors[:rules]).to include("'match' must be one of: all, any")
    end

    it "rejects a non-boolean negation" do
      smart_playlist = build(:smart_playlist, rules: { "match" => "all", "rules" => [], "not" => "yes" })

      expect(smart_playlist).not_to be_valid
      expect(smart_playlist.errors[:rules]).to include("'not' must be true or false")
    end

    it "accepts a boolean negation" do
      expect(build(:smart_playlist, rules: { "match" => "all", "rules" => [], "not" => true })).to be_valid
    end

    it "rejects a rules list that is not a list" do
      smart_playlist = build(:smart_playlist, rules: { "match" => "all", "rules" => "everything" })

      expect(smart_playlist).not_to be_valid
      expect(smart_playlist.errors[:rules]).to include("'rules' must be a list")
    end

    it "validates conditions inside nested groups" do
      smart_playlist = with_rules([
                                    { "match" => "any",
                                      "rules" => [{ "field" => "nope", "operator" => "equals", "value" => "x" }], },
                                  ])

      expect(smart_playlist).not_to be_valid
      expect(smart_playlist.errors[:rules]).to include('has an unknown field: "nope"')
    end

    it "rejects a tree nested deeper than the limit" do
      deepest = { "field" => "genre", "operator" => "equals", "value" => "rock" }
      rules = (RuleSetValidator::MAX_DEPTH + 1).downto(1).reduce(deepest) do |inner, _level|
        { "match" => "all", "rules" => [inner] }
      end

      smart_playlist = build(:smart_playlist, rules: rules)

      expect(smart_playlist).not_to be_valid
      expect(smart_playlist.errors[:rules])
        .to include("is nested more than #{RuleSetValidator::MAX_DEPTH} levels deep")
    end

    it "rejects more rules than the limit" do
      condition = { "field" => "genre", "operator" => "equals", "value" => "rock" }
      smart_playlist = with_rules(Array.new(RuleSetValidator::MAX_NODES + 1) { condition })

      expect(smart_playlist).not_to be_valid
      expect(smart_playlist.errors[:rules])
        .to include("cannot contain more than #{RuleSetValidator::MAX_NODES} rules")
    end

    it "accepts a tree at the limits" do
      condition = { "field" => "genre", "operator" => "equals", "value" => "rock" }
      # The root group counts as a node, so MAX_NODES - 1 conditions fit beneath it.
      expect(with_rules(Array.new(RuleSetValidator::MAX_NODES - 1) { condition })).to be_valid
    end
  end

  describe "#ready?" do
    it "is false for an empty ruleset" do
      expect(build(:smart_playlist)).not_to be_ready
    end

    it "is true once a rule is present" do
      expect(build(:smart_playlist, :with_rules)).to be_ready
    end
  end

  describe "ownership" do
    it "derives the user and name from the target playlist" do
      target = create(:playlist, :with_spotify, name: "Metal Mix")
      smart_playlist = create(:smart_playlist, target_playlist: target)

      expect(smart_playlist.user).to eq(target.user)
      expect(smart_playlist.name).to eq("Metal Mix")
    end

    it "is reachable from the user through their playlists" do
      smart_playlist = create(:smart_playlist)

      expect(smart_playlist.user.smart_playlists).to contain_exactly(smart_playlist)
    end

    it "is destroyed along with its target playlist, leaving sources intact" do
      smart_playlist = create(:smart_playlist)
      source = smart_playlist.smart_playlist_sources.first.playlist

      expect { smart_playlist.target_playlist.destroy! }.to change(described_class, :count).by(-1)
      expect(source.reload).to be_persisted
    end

    it "does not remove the target playlist when destroyed" do
      smart_playlist = create(:smart_playlist)
      target = smart_playlist.target_playlist

      smart_playlist.destroy!

      expect(target.reload).to be_persisted
      expect(SmartPlaylistSource.count).to eq(0)
    end
  end

  describe "scopes" do
    describe ".enabled" do
      let!(:enabled) { create(:smart_playlist, :enabled) }
      let!(:disabled) { create(:smart_playlist) }

      it "returns only enabled smart playlists" do
        expect(described_class.enabled).to contain_exactly(enabled)
        expect(described_class.enabled).not_to include(disabled)
      end
    end

    describe ".needs_evaluation" do
      let!(:never_evaluated) { create(:smart_playlist, :enabled, last_evaluated_at: nil) }
      let!(:stale) { create(:smart_playlist, :enabled, last_evaluated_at: 2.days.ago) }
      let!(:recent) { create(:smart_playlist, :enabled, last_evaluated_at: 1.hour.ago) }
      let!(:disabled) { create(:smart_playlist, last_evaluated_at: nil) }

      it "returns enabled smart playlists that need evaluation" do
        expect(described_class.needs_evaluation).to contain_exactly(never_evaluated, stale)
        expect(described_class.needs_evaluation).not_to include(recent, disabled)
      end
    end
  end
end
