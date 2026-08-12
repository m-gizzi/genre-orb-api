# frozen_string_literal: true

require "rails_helper"

RSpec.describe SmartPlaylists::PushTrackSet do
  let(:user) { create(:user) }
  let(:target) { create(:playlist, :with_spotify, user: user) }
  let(:any_rules) { SmartPlaylist::EMPTY_RULES.deep_dup }

  def smart_playlist_holding(memberships)
    source = create(:playlist, :holding, user: user, memberships: memberships)
    create(:smart_playlist, target_playlist: target, rules: any_rules, source_playlists: [source])
  end

  def track_set(smart_playlist)
    described_class.new(SmartPlaylists::Evaluator.new(smart_playlist))
  end

  describe "#entries" do
    it "returns the matches newest-added first, tie-broken on track id" do
      oldest = create(:track)
      newest = create(:track)
      smart_playlist = smart_playlist_holding([[oldest, 3.days.ago], [newest, 1.hour.ago]])

      expect(track_set(smart_playlist).entries.map(&:track_id)).to eq([newest.id, oldest.id])
    end

    it "carries the membership added_at" do
      added_at = 2.days.ago
      track = create(:track)
      smart_playlist = smart_playlist_holding([[track, added_at]])

      entry = track_set(smart_playlist).entries.sole

      expect(entry.track_id).to eq(track.id)
      expect(entry.added_at).to be_within(1.second).of(added_at)
    end

    it "yields one entry per track even when two sources hold it" do
      track = create(:track)
      first = create(:playlist, :holding, user: user, tracks: [track])
      second = create(:playlist, :holding, user: user, tracks: [track])
      smart_playlist = create(:smart_playlist, target_playlist: target, rules: any_rules,
                                               source_playlists: [first, second],)

      expect(track_set(smart_playlist).entries.map(&:track_id)).to eq([track.id])
    end

    it "is empty when the rules match nothing" do
      source = create(:playlist, :holding, user: user, tracks: [create(:track)])
      smart_playlist = create(:smart_playlist, target_playlist: target, source_playlists: [source],
                                               rules: { "match" => "all",
                                                        "rules" => [{ "field" => "title", "operator" => "equals",
                                                                      "value" => "nope", }], },)

      expect(track_set(smart_playlist).entries).to be_empty
    end
  end

  describe "the query timeout" do
    it "caps each query itself, so no caller has to force one first" do
      smart_playlist = smart_playlist_holding([[create(:track), 1.hour.ago]])
      allow(SmartPlaylists::QueryTimeout).to receive(:guard).and_raise(ActiveRecord::QueryCanceled)

      expect { track_set(smart_playlist).entries }.to raise_error(ActiveRecord::QueryCanceled)
      expect { track_set(smart_playlist).total_match_count }.to raise_error(ActiveRecord::QueryCanceled)
    end
  end

  describe "sampling above the push limit" do
    before { stub_const("#{described_class}::PUSH_LIMIT", 3) }

    let(:smart_playlist) do
      tracks = create_list(:track, 5)
      smart_playlist_holding(tracks.map.with_index { |track, i| [track, i.days.ago] })
    end

    it "reports the full match count, not the sampled size" do
      set = track_set(smart_playlist)

      expect(set.total_match_count).to eq(5)
      expect(set.sampled?).to be(true)
      expect(set.entries.size).to eq(3)
    end

    it "still returns the sample in canonical order" do
      entries = track_set(smart_playlist).entries

      expect(entries.map(&:added_at)).to eq(entries.map(&:added_at).sort.reverse)
    end

    it "rotates the selection between runs" do
      selections = Array.new(12) { track_set(smart_playlist).entries.map(&:track_id).sort }

      expect(selections.uniq.size).to be > 1
    end

    it "does not sample at exactly the limit" do
      tracks = create_list(:track, 3)
      exact = smart_playlist_holding(tracks.map { |track| [track, 1.hour.ago] })

      set = track_set(exact)

      expect(set.sampled?).to be(false)
      expect(set.entries.size).to eq(3)
    end
  end
end
