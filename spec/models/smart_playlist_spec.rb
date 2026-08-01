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

    it "rejects rules without match and rules keys" do
      smart_playlist = build(:smart_playlist, rules: { "foo" => "bar" })

      expect(smart_playlist).not_to be_valid
      expect(smart_playlist.errors[:rules]).to include("must have 'match' and 'rules' keys")
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
