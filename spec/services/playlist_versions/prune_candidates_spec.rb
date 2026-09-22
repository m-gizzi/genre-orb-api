# frozen_string_literal: true

require "rails_helper"

RSpec.describe PlaylistVersions::PruneCandidates do
  let(:playlist) { create(:playlist) }

  def version(number, on: playlist, created_at: 1.day.ago)
    create(:playlist_version, playlist: on, version_number: number, created_at: created_at)
  end

  def candidates(ids = [playlist.id], keep: 3, before: 1.hour.ago)
    described_class.new(ids, keep: keep, before: before).call
  end

  it "returns the versions ranked past the retention window" do
    olds = [version(1), version(2), version(3)]
    3.times { |i| version(4 + i) }

    expect(candidates).to match_array(olds.map(&:id))
  end

  it "keeps the newest versions" do
    version(1)
    keepers = [version(2), version(3), version(4)]

    expect(candidates).not_to include(*keepers.map(&:id))
  end

  it "returns nothing when the playlist has exactly the retained count" do
    3.times { |i| version(i + 1) }

    expect(candidates).to be_empty
  end

  it "returns nothing for a playlist with no versions" do
    expect(candidates).to be_empty
  end

  it "keeps the current version even when it ranks far below the window" do
    oldest = version(1)
    (2..6).each { |n| version(n) }
    playlist.update!(current_version: oldest)

    expect(candidates).not_to include(oldest.id)
  end

  it "still prunes the rest when the current version ranks below the window" do
    oldest = version(1)
    stale = version(2)
    (3..6).each { |n| version(n) }
    playlist.update!(current_version: oldest)

    expect(candidates).to include(stale.id)
  end

  it "ranks each playlist independently" do
    other = create(:playlist)
    old = version(1)
    (2..4).each { |n| version(n) }
    other_keepers = (1..3).map { |n| version(n, on: other) }

    expect(candidates([playlist.id, other.id])).to contain_exactly(old.id)
    expect(candidates([playlist.id, other.id])).not_to include(*other_keepers.map(&:id))
  end

  it "ignores playlists outside the given chunk" do
    other = create(:playlist)
    (1..5).each { |n| version(n, on: other) }

    expect(candidates).to be_empty
  end

  it "spares a version still inside the grace window" do
    fresh = version(1, created_at: Time.current)
    (2..5).each { |n| version(n) }

    expect(candidates).not_to include(fresh.id)
  end

  it "returns nothing when given no playlists" do
    (1..5).each { |n| version(n) }

    expect(candidates([])).to be_empty
  end
end
