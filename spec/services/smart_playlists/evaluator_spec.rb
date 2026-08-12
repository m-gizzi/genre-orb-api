# frozen_string_literal: true

require "rails_helper"

RSpec.describe SmartPlaylists::Evaluator do
  let(:user) { create(:user) }
  let(:target) { create(:playlist, :with_spotify, user: user) }

  def smart_playlist_for(tracks, rules:, added_at: Time.current, memberships: nil)
    source = create(:playlist, :holding, user: user, tracks: tracks || [],
                                         added_at: added_at, memberships: memberships,)
    create(:smart_playlist, target_playlist: target, rules: rules, source_playlists: [source])
  end

  def condition(field, operator, value)
    { "match" => "all", "rules" => [{ "field" => field, "operator" => operator, "value" => value }] }
  end

  def matches(smart_playlist)
    described_class.new(smart_playlist).matches.to_a
  end

  describe "the source pool" do
    it "matches only tracks on the sources' current versions" do
      inside = create(:track)
      outside = create(:track, :in_library, user: user)

      smart_playlist = smart_playlist_for([inside], rules: SmartPlaylist::EMPTY_RULES.deep_dup)

      expect(matches(smart_playlist)).to contain_exactly(inside)
      expect(matches(smart_playlist)).not_to include(outside)
    end

    it "draws nothing from a source that has never been synced" do
      unsynced = create(:playlist, user: user)
      smart_playlist = create(:smart_playlist, target_playlist: target, source_playlists: [unsynced],
                                               rules: SmartPlaylist::EMPTY_RULES.deep_dup,)

      expect(matches(smart_playlist)).to be_empty
      expect(described_class.new(smart_playlist).source_track_count).to eq(0)
    end

    it "counts a track once even when two sources hold it" do
      track = create(:track)
      first = create(:playlist, :holding, user: user, tracks: [track])
      second = create(:playlist, :holding, user: user, tracks: [track])
      smart_playlist = create(:smart_playlist, target_playlist: target, source_playlists: [first, second],
                                               rules: SmartPlaylist::EMPTY_RULES.deep_dup,)

      expect(matches(smart_playlist)).to contain_exactly(track)
      expect(described_class.new(smart_playlist).count).to eq(1)
    end

    it "counts a track once even when one playlist holds it twice" do
      track = create(:track)
      now = Time.current
      smart_playlist = smart_playlist_for(nil, rules: SmartPlaylist::EMPTY_RULES.deep_dup,
                                               memberships: [[track, now], [track, now]],)

      expect(matches(smart_playlist)).to contain_exactly(track)
    end
  end

  describe "an empty rule set" do
    it "matches the whole pool for match: all" do
      tracks = create_list(:track, 2)
      smart_playlist = smart_playlist_for(tracks, rules: { "match" => "all", "rules" => [] })

      expect(matches(smart_playlist)).to match_array(tracks)
    end

    it "matches nothing for match: any" do
      smart_playlist = smart_playlist_for(create_list(:track, 2), rules: { "match" => "any", "rules" => [] })

      expect(matches(smart_playlist)).to be_empty
    end
  end

  describe "negation on multi-valued fields" do
    it "excludes a track credited to the named artist even when it has others" do
      gojira = create(:artist, name: "Gojira")
      other = create(:artist, name: "Other")
      both = create(:track, :with_artists, artists: [gojira, other])
      neither = create(:track, :with_artists, artists: [other])

      smart_playlist = smart_playlist_for([both, neither], rules: condition("artist", "not_equals", "Gojira"))

      expect(matches(smart_playlist)).to contain_exactly(neither)
    end

    it "matches a track with no genres at all" do
      tagged = create(:track, :with_genres, genre_names: ["metal"])
      untagged = create(:track)

      smart_playlist = smart_playlist_for([tagged, untagged], rules: condition("genre", "not_equals", "metal"))

      expect(matches(smart_playlist)).to contain_exactly(untagged)
    end

    it "matches a track whose album has no release year" do
      dated = create(:track, album: create(:album, release_year: 2020))
      undated = create(:track, album: create(:album, release_year: nil))

      smart_playlist = smart_playlist_for([dated, undated], rules: condition("year", "not_equals", 2020))

      expect(matches(smart_playlist)).to contain_exactly(undated)
    end

    it "reads a NOT group as the complement of what the group matches" do
      metal = create(:track, :with_genres, genre_names: ["metal"])
      rock = create(:track, :with_genres, genre_names: ["rock"])
      rules = {
        "match" => "all",
        "rules" => [{ "match" => "any", "not" => true,
                      "rules" => [{ "field" => "genre", "operator" => "equals", "value" => "metal" }], }],
      }

      smart_playlist = smart_playlist_for([metal, rock], rules: rules)

      expect(matches(smart_playlist)).to contain_exactly(rock)
    end
  end

  describe "genre matching" do
    it "ignores the casing and spacing a rule was typed with" do
      track = create(:track, :with_genres, genre_names: ["death metal"])

      smart_playlist = smart_playlist_for([track], rules: condition("genre", "equals", "  Death   Metal "))

      expect(matches(smart_playlist)).to contain_exactly(track)
    end

    it "matches a track once when two sources attributed the same genre" do
      track = create(:track)
      genre = create(:genre, name: "metal")
      create(:track_genre, track: track, genre: genre, source: :spotify)
      create(:track_genre, track: track, genre: genre, source: :user)

      smart_playlist = smart_playlist_for([track], rules: condition("genre", "equals", "metal"))

      expect(matches(smart_playlist)).to contain_exactly(track)
    end
  end

  describe "presence operators" do
    it "matches only the tracks carrying no genre at all" do
      tagged = create(:track, :with_genres, genre_names: ["metal"])
      untagged = create(:track)

      smart_playlist = smart_playlist_for([tagged, untagged], rules: condition("genre", "is_not_set", nil))

      expect(matches(smart_playlist)).to contain_exactly(untagged)
    end

    it "matches the tracks carrying any genre for is_set" do
      tagged = create(:track, :with_genres, genre_names: ["metal"])
      untagged = create(:track)

      smart_playlist = smart_playlist_for([tagged, untagged], rules: condition("genre", "is_set", nil))

      expect(matches(smart_playlist)).to contain_exactly(tagged)
    end

    it "does not care which genre a track carries" do
      metal = create(:track, :with_genres, genre_names: ["metal"])
      rock = create(:track, :with_genres, genre_names: ["rock"])

      smart_playlist = smart_playlist_for([metal, rock], rules: condition("genre", "is_not_set", nil))

      expect(matches(smart_playlist)).to be_empty
    end
  end

  describe "playlist membership" do
    it "drops tracks held by an excluded playlist" do
      shared = create(:track)
      only_source = create(:track)
      excluded = create(:playlist, :holding, user: user, tracks: [shared])

      smart_playlist = smart_playlist_for([shared, only_source],
                                          rules: condition("playlist", "not_in", [excluded.id]),)

      expect(matches(smart_playlist)).to contain_exactly(only_source)
    end

    it "keeps only tracks held by a named playlist" do
      shared = create(:track)
      only_source = create(:track)
      named = create(:playlist, :holding, user: user, tracks: [shared])

      smart_playlist = smart_playlist_for([shared, only_source], rules: condition("playlist", "in", [named.id]))

      expect(matches(smart_playlist)).to contain_exactly(shared)
    end

    it "excludes nothing for a playlist that has never been synced" do
      track = create(:track)
      unsynced = create(:playlist, user: user)

      smart_playlist = smart_playlist_for([track], rules: condition("playlist", "not_in", [unsynced.id]))

      expect(matches(smart_playlist)).to contain_exactly(track)
    end

    it "reads membership from the current version only" do
      track = create(:track)
      stale = create(:playlist, :holding, user: user, tracks: [track])
      stale.update!(current_version: create(:playlist_version, playlist: stale, version_number: 99))

      smart_playlist = smart_playlist_for([track], rules: condition("playlist", "not_in", [stale.id]))

      expect(matches(smart_playlist)).to contain_exactly(track)
    end
  end

  describe "nested groups" do
    it "intersects an all group and unions an any group" do
      recent_metal = create(:track, :with_genres, genre_names: ["metal"], album: create(:album, release_year: 2021))
      older_metal = create(:track, :with_genres, genre_names: ["metal"], album: create(:album, release_year: 2010))
      recent_rock = create(:track, :with_genres, genre_names: ["rock"], album: create(:album, release_year: 2021))

      rules = {
        "match" => "all",
        "rules" => [
          { "field" => "genre", "operator" => "equals", "value" => "metal" },
          { "match" => "any",
            "rules" => [
              { "field" => "year", "operator" => "greater_than", "value" => 2020 },
              { "field" => "year", "operator" => "less_than", "value" => 1990 },
            ], },
        ],
      }

      smart_playlist = smart_playlist_for([recent_metal, older_metal, recent_rock], rules: rules)

      expect(matches(smart_playlist)).to contain_exactly(recent_metal)
    end
  end

  describe "date_added" do
    it "uses the earliest add across the sources" do
      track = create(:track)
      old_source = create(:playlist, :holding, user: user, tracks: [track], added_at: 90.days.ago)
      new_source = create(:playlist, :holding, user: user, tracks: [track], added_at: 1.day.ago)
      smart_playlist = create(:smart_playlist, target_playlist: target,
                                               source_playlists: [old_source, new_source],
                                               rules: condition("date_added", "in_the_last",
                                                                { "count" => 30, "unit" => "days" }),)

      expect(matches(smart_playlist)).to be_empty
    end

    it "treats a missing added_at as outside any recent window" do
      recent = create(:track)
      unknown = create(:track)
      smart_playlist = smart_playlist_for(
        nil,
        rules: condition("date_added", "in_the_last", { "count" => 30, "unit" => "days" }),
        memberships: [[recent, 1.day.ago], [unknown, nil]],
      )

      expect(matches(smart_playlist)).to contain_exactly(recent)
    end

    it "includes a missing added_at in not_in_the_last, which is the complement" do
      recent = create(:track)
      unknown = create(:track)
      smart_playlist = smart_playlist_for(
        nil,
        rules: condition("date_added", "not_in_the_last", { "count" => 30, "unit" => "days" }),
        memberships: [[recent, 1.day.ago], [unknown, nil]],
      )

      expect(matches(smart_playlist)).to contain_exactly(unknown)
    end
  end

  describe "ordering" do
    it "returns newest-added first, with unknown dates last" do
      oldest = create(:track, title: "oldest")
      newest = create(:track, title: "newest")
      unknown = create(:track, title: "unknown")
      smart_playlist = smart_playlist_for(
        nil,
        rules: SmartPlaylist::EMPTY_RULES.deep_dup,
        memberships: [[oldest, 10.days.ago], [newest, 1.day.ago], [unknown, nil]],
      )

      expect(matches(smart_playlist)).to eq([newest, oldest, unknown])
    end
  end

  describe "a rules override" do
    it "evaluates the given set instead of the persisted one" do
      metal = create(:track, :with_genres, genre_names: ["metal"])
      rock = create(:track, :with_genres, genre_names: ["rock"])
      smart_playlist = smart_playlist_for([metal, rock], rules: condition("genre", "equals", "metal"))

      evaluator = described_class.new(smart_playlist, rules: condition("genre", "equals", "rock"))

      expect(evaluator.matches.to_a).to contain_exactly(rock)
    end
  end

  describe "#count" do
    it "counts matches without loading them" do
      tracks = create_list(:track, 3, :with_genres, genre_names: ["metal"])
      create(:track)
      smart_playlist = smart_playlist_for(tracks, rules: condition("genre", "equals", "metal"))

      expect(described_class.new(smart_playlist).count).to eq(3)
    end
  end

  describe "a tree at the catalog's limits" do
    def nest(depth, leaf)
      return leaf if depth.zero?

      { "match" => "any", "rules" => [nest(depth - 1, leaf)] }
    end

    it "compiles and runs" do
      track = create(:track, :with_genres, genre_names: ["metal"])
      leaf = { "field" => "genre", "operator" => "equals", "value" => "metal" }
      deepest = nest(Rules::FieldCatalog::MAX_DEPTH - 1, leaf)
      wide = Array.new(Rules::FieldCatalog::MAX_NODES - 10) { leaf }
      smart_playlist = smart_playlist_for([track], rules: { "match" => "all",
                                                            "rules" => [deepest, *wide], },)

      expect(smart_playlist).to be_valid
      expect(matches(smart_playlist)).to contain_exactly(track)
    end
  end

  describe "recording" do
    let(:metal_rules) do
      { "match" => "all", "rules" => [{ "field" => "genre", "operator" => "equals", "value" => "metal" }] }
    end

    def evaluator_for(rules_override = nil)
      track = create(:track, :with_genres, genre_names: ["metal"])
      smart_playlist = smart_playlist_for([track, create(:track)], rules: metal_rules)
      args = rules_override ? { rules: rules_override } : {}

      [smart_playlist, described_class.new(smart_playlist, **args)]
    end

    it "records the count and the time when it evaluated the saved rules" do
      smart_playlist, evaluator = evaluator_for

      expect(evaluator.record!).to be_within(5.seconds).of(Time.current)
      expect(smart_playlist.reload.match_count).to eq(1)
      expect(smart_playlist.last_evaluated_at).to be_present
    end

    it "records a drop to zero matches" do
      smart_playlist = smart_playlist_for([create(:track)], rules: metal_rules)
      smart_playlist.update_column(:match_count, 7)

      described_class.new(smart_playlist).record!

      expect(smart_playlist.reload.match_count).to eq(0)
    end

    it "does not record a draft the record does not hold" do
      draft = { "match" => "all", "rules" => [{ "field" => "genre", "operator" => "equals", "value" => "rock" }] }
      smart_playlist, evaluator = evaluator_for(draft)

      expect(evaluator).not_to be_records
      expect(evaluator.record!).to be_nil
      expect(smart_playlist.reload.last_evaluated_at).to be_nil
    end

    it "records a draft that is the saved rules under a different key order" do
      reordered = { "rules" => metal_rules["rules"], "match" => "all" }
      _smart_playlist, evaluator = evaluator_for(reordered)

      expect(evaluator).to be_records
    end

    it "does not record an empty rule set, which matches the whole pool" do
      smart_playlist = smart_playlist_for(create_list(:track, 2),
                                          rules: SmartPlaylist::EMPTY_RULES.deep_dup,)
      evaluator = described_class.new(smart_playlist)

      expect(evaluator.count).to eq(2)
      expect(evaluator).not_to be_records
      expect(evaluator.record!).to be_nil
      expect(smart_playlist.reload.last_evaluated_at).to be_nil
    end

    it "writes no PlaylistVersion — the target still holds what Spotify holds" do
      smart_playlist, evaluator = evaluator_for

      expect { evaluator.record! }.not_to change(PlaylistVersion, :count)
      expect(smart_playlist.target_playlist.reload.current_version_id).to be_nil
    end

    it "counts once even when the count is read again" do
      _smart_playlist, evaluator = evaluator_for
      evaluator.count

      expect { evaluator.record! }.not_to change(evaluator, :count)
    end
  end
end
