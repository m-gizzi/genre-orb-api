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
      expect(smart_playlist.errors[:rules]).to include('has an unknown field: "bpm" at rule 1')
    end

    it "rejects an unknown operator" do
      smart_playlist = with_rules([{ "field" => "genre", "operator" => "matches_sql", "value" => "x" }])

      expect(smart_playlist).not_to be_valid
      expect(smart_playlist.errors[:rules]).to include('has an unknown operator: "matches_sql" at rule 1')
    end

    it "rejects a rule with no value" do
      smart_playlist = with_rules([{ "field" => "genre", "operator" => "equals" }])

      expect(smart_playlist).not_to be_valid
      expect(smart_playlist.errors[:rules]).to include("each rule must have a value at rule 1")
    end

    it "accepts a false value where the field is boolean" do
      expect(with_rules([{ "field" => "explicit", "operator" => "equals", "value" => false }])).to be_valid
    end

    it "rejects a field the catalog dropped" do
      smart_playlist = with_rules([{ "field" => "play_count", "operator" => "greater_than", "value" => 5 }])

      expect(smart_playlist).not_to be_valid
      expect(smart_playlist.errors[:rules]).to include('has an unknown field: "play_count" at rule 1')
    end

    it "rejects an operator the field does not support" do
      smart_playlist = with_rules([{ "field" => "genre", "operator" => "greater_than", "value" => "rock" }])

      expect(smart_playlist).not_to be_valid
      expect(smart_playlist.errors[:rules])
        .to include('does not support the operator "greater_than" on the field "genre" at rule 1')
    end

    it "rejects a list operator given a scalar" do
      smart_playlist = with_rules([{ "field" => "artist", "operator" => "in", "value" => "Gojira" }])

      expect(smart_playlist).not_to be_valid
      expect(smart_playlist.errors[:rules])
        .to include("must have at least one value when matching a list at rule 1")
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
        .to include("must have exactly two values when comparing a range at rule 1")
    end

    it "accepts a range operator given two values" do
      expect(
        with_rules([{ "field" => "year", "operator" => "between", "value" => [2020, 2024] }]),
      ).to be_valid
    end

    it "rejects a range whose bounds are the wrong way round" do
      smart_playlist = with_rules([{ "field" => "year", "operator" => "between", "value" => [2024, 2020] }])

      expect(smart_playlist).not_to be_valid
      expect(smart_playlist.errors[:rules])
        .to include("must not have a lower bound greater than its upper bound at rule 1")
    end

    it "accepts a range whose bounds are equal" do
      expect(
        with_rules([{ "field" => "year", "operator" => "between", "value" => [2020, 2020] }]),
      ).to be_valid
    end

    it "rejects a scalar operator given a blank value" do
      smart_playlist = with_rules([{ "field" => "title", "operator" => "contains", "value" => "" }])

      expect(smart_playlist).not_to be_valid
      expect(smart_playlist.errors[:rules]).to include("must not be blank at rule 1")
    end

    it "rejects a whitespace-only value" do
      smart_playlist = with_rules([{ "field" => "genre", "operator" => "equals", "value" => "   " }])

      expect(smart_playlist).not_to be_valid
      expect(smart_playlist.errors[:rules]).to include("must not be blank at rule 1")
    end

    it "rejects a list longer than the cap" do
      values = Array.new(Rules::FieldCatalog::MAX_LIST_SIZE + 1) { |index| "Artist #{index}" }
      smart_playlist = with_rules([{ "field" => "artist", "operator" => "in", "value" => values }])

      expect(smart_playlist).not_to be_valid
      expect(smart_playlist.errors[:rules])
        .to include("cannot match more than #{Rules::FieldCatalog::MAX_LIST_SIZE} values at once at rule 1")
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
        .to include("must use one of these units: #{Rules::FieldCatalog::RELATIVE_UNITS.join(", ")} at rule 1")
    end

    it "rejects a relative date with a non-positive count" do
      smart_playlist = with_rules([
                                    { "field" => "date_added", "operator" => "in_the_last",
                                      "value" => { "count" => 0, "unit" => "days" }, },
                                  ])

      expect(smart_playlist).not_to be_valid
      expect(smart_playlist.errors[:rules]).to include("must have a whole number count at rule 1")
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
      expect(smart_playlist.errors[:rules]).to include('has an unknown field: "nope" at rule 1.1')
    end

    it "rejects a tree nested deeper than the limit" do
      deepest = { "field" => "genre", "operator" => "equals", "value" => "rock" }
      rules = (Rules::FieldCatalog::MAX_DEPTH + 1).downto(1).reduce(deepest) do |inner, _level|
        { "match" => "all", "rules" => [inner] }
      end

      smart_playlist = build(:smart_playlist, rules: rules)

      expect(smart_playlist).not_to be_valid
      expect(smart_playlist.errors[:rules])
        .to include("is nested more than #{Rules::FieldCatalog::MAX_DEPTH} levels deep at group 1.1.1.1.1")
    end

    it "rejects more rules than the limit, reporting it once at the root" do
      condition = { "field" => "genre", "operator" => "equals", "value" => "rock" }
      smart_playlist = with_rules(Array.new(Rules::FieldCatalog::MAX_NODES + 5) { condition })

      expect(smart_playlist).not_to be_valid
      expect(smart_playlist.errors[:rules])
        .to eq(["cannot contain more than #{Rules::FieldCatalog::MAX_NODES} rules"])
    end

    it "accepts a tree at the limits" do
      condition = { "field" => "genre", "operator" => "equals", "value" => "rock" }
      # The root group counts as a node, so MAX_NODES - 1 conditions fit beneath it.
      expect(with_rules(Array.new(Rules::FieldCatalog::MAX_NODES - 1) { condition })).to be_valid
    end

    describe "value typing" do
      it "rejects text where the field expects a number" do
        smart_playlist = with_rules([{ "field" => "year", "operator" => "greater_than", "value" => "banana" }])

        expect(smart_playlist).not_to be_valid
        expect(smart_playlist.errors[:rules]).to include("must be a whole number at rule 1")
      end

      it "rejects a number where the field expects text" do
        smart_playlist = with_rules([{ "field" => "genre", "operator" => "equals", "value" => 42 }])

        expect(smart_playlist).not_to be_valid
        expect(smart_playlist.errors[:rules]).to include("must be text at rule 1")
      end

      it "rejects a non-boolean on a boolean field" do
        smart_playlist = with_rules([{ "field" => "explicit", "operator" => "equals", "value" => "yes" }])

        expect(smart_playlist).not_to be_valid
        expect(smart_playlist.errors[:rules]).to include("must be true or false at rule 1")
      end

      it "rejects a popularity outside Spotify's range" do
        smart_playlist = with_rules([{ "field" => "popularity", "operator" => "equals", "value" => 500 }])

        expect(smart_playlist).not_to be_valid
        expect(smart_playlist.errors[:rules]).to include("must be between 0 and 100 at rule 1")
      end

      it "rejects a negative duration" do
        smart_playlist = with_rules([{ "field" => "duration", "operator" => "greater_than", "value" => -1 }])

        expect(smart_playlist).not_to be_valid
        expect(smart_playlist.errors[:rules]).to include("must be between 0 and 86400000 at rule 1")
      end

      it "rejects text longer than the cap" do
        long = "a" * (Rules::FieldCatalog::MAX_STRING_LENGTH + 1)
        smart_playlist = with_rules([{ "field" => "title", "operator" => "contains", "value" => long }])

        expect(smart_playlist).not_to be_valid
        expect(smart_playlist.errors[:rules])
          .to include("must be #{Rules::FieldCatalog::MAX_STRING_LENGTH} characters or fewer at rule 1")
      end

      it "accepts an ISO date on date_added" do
        expect(
          with_rules([{ "field" => "date_added", "operator" => "greater_than", "value" => "2024-01-15" }]),
        ).to be_valid
      end

      it "rejects a date that isn't ISO 8601" do
        smart_playlist = with_rules([{ "field" => "date_added", "operator" => "greater_than",
                                       "value" => "15/01/2024", }])

        expect(smart_playlist).not_to be_valid
        expect(smart_playlist.errors[:rules]).to include("must be a date in YYYY-MM-DD form at rule 1")
      end

      it "rejects a date that looks ISO but isn't real" do
        smart_playlist = with_rules([{ "field" => "date_added", "operator" => "greater_than",
                                       "value" => "2024-02-31", }])

        expect(smart_playlist).not_to be_valid
        expect(smart_playlist.errors[:rules]).to include("must be a date in YYYY-MM-DD form at rule 1")
      end

      it "type-checks every value in a list" do
        smart_playlist = with_rules([{ "field" => "artist", "operator" => "in", "value" => ["Gojira", 7] }])

        expect(smart_playlist).not_to be_valid
        expect(smart_playlist.errors[:rules]).to include("must be text at rule 1")
      end
    end

    describe "empty groups" do
      it "rejects a nested group with no rules" do
        smart_playlist = with_rules([{ "match" => "all", "rules" => [] }])

        expect(smart_playlist).not_to be_valid
        expect(smart_playlist.errors[:rules]).to include("must contain at least one rule at group 1")
      end

      it "still accepts an empty root, which is the draft state" do
        expect(build(:smart_playlist, rules: SmartPlaylist::EMPTY_RULES.deep_dup)).to be_valid
      end

      it "keeps #ready? honest, since a root holding only an empty group cannot be saved" do
        smart_playlist = with_rules([{ "match" => "all", "rules" => [] }])

        expect(smart_playlist).to be_ready
        expect(smart_playlist).not_to be_valid
      end
    end

    describe "unexpected keys" do
      it "rejects a rule carrying keys the schema does not describe" do
        smart_playlist = with_rules([{ "field" => "genre", "operator" => "equals", "value" => "rock",
                                       "junk" => "smuggled", }])

        expect(smart_playlist).not_to be_valid
        expect(smart_playlist.errors[:rules]).to include('has unexpected keys: "junk" at rule 1')
      end

      it "rejects a group carrying keys the schema does not describe" do
        smart_playlist = build(:smart_playlist,
                               rules: { "match" => "all", "junk" => "smuggled", "rules" => [] },)

        expect(smart_playlist).not_to be_valid
        expect(smart_playlist.errors[:rules]).to include('has unexpected keys: "junk"')
      end

      it "accepts the keys a group is allowed to carry" do
        expect(
          build(:smart_playlist, rules: { "match" => "any", "not" => true, "rules" => [
                  { "field" => "genre", "operator" => "equals", "value" => "rock" },
                ], },),
        ).to be_valid
      end
    end

    describe "echoing what the client sent" do
      it "truncates an oversized field name rather than quoting it in full" do
        smart_playlist = with_rules([{ "field" => "b" * 300, "operator" => "equals", "value" => "x" }])

        expect(smart_playlist).not_to be_valid
        expect(smart_playlist.errors[:rules].first.length)
          .to be < Rules::Excerpt::MAX_LENGTH + 40
      end

      it "reports only the first few unexpected keys" do
        junk = Array.new(Rules::Excerpt::MAX_ENTRIES + 3) { |index| ["junk#{index}", 1] }.to_h
        smart_playlist = with_rules([
                                      { "field" => "genre", "operator" => "equals",
                                        "value" => "rock", }.merge(junk),
                                    ])

        expect(smart_playlist).not_to be_valid
        expect(smart_playlist.errors[:rules].first.scan("junk").size)
          .to eq(Rules::Excerpt::MAX_ENTRIES)
      end
    end

    describe "locating failures" do
      it "reports each failing rule separately rather than collapsing them" do
        smart_playlist = with_rules([
                                      { "field" => "year", "operator" => "equals", "value" => "banana" },
                                      { "field" => "genre", "operator" => "equals", "value" => "rock" },
                                      { "field" => "popularity", "operator" => "equals", "value" => "banana" },
                                    ])

        expect(smart_playlist).not_to be_valid
        expect(smart_playlist.errors[:rules])
          .to contain_exactly("must be a whole number at rule 1", "must be a whole number at rule 3")
      end

      it "numbers rules inside nested groups from their parent" do
        smart_playlist = with_rules([
                                      { "field" => "genre", "operator" => "equals", "value" => "rock" },
                                      { "match" => "any",
                                        "rules" => [
                                          { "field" => "genre", "operator" => "equals", "value" => "jazz" },
                                          { "field" => "year", "operator" => "equals", "value" => "banana" },
                                        ], },
                                    ])

        expect(smart_playlist).not_to be_valid
        expect(smart_playlist.errors[:rules]).to contain_exactly("must be a whole number at rule 2.2")
      end
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
