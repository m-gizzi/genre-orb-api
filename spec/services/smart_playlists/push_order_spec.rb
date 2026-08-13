# frozen_string_literal: true

require "rails_helper"

RSpec.describe SmartPlaylists::PushOrder do
  subject(:order) { described_class.new(user) }

  let(:user) { create(:user) }

  def smart_playlist(*traits, sources: nil, **attributes)
    attributes[:source_playlists] = sources if sources
    create(:smart_playlist, :enabled, *traits, user: user, **attributes)
  end

  def wave_ids
    order.waves.map { |wave| wave.map(&:id).sort }
  end

  it "puts a chain in one playlist per wave" do
    first = smart_playlist
    second = smart_playlist(sources: [first.target_playlist])
    third = smart_playlist(sources: [second.target_playlist])

    expect(wave_ids).to eq([[first.id], [second.id], [third.id]])
  end

  it "runs a diamond's independent middles in the same wave" do
    top = smart_playlist
    left = smart_playlist(sources: [top.target_playlist])
    right = smart_playlist(sources: [top.target_playlist])
    bottom = smart_playlist(sources: [left.target_playlist, right.target_playlist])

    expect(wave_ids).to eq([[top.id], [left.id, right.id].sort, [bottom.id]])
  end

  it "orders on an edge that exists only inside a rule" do
    upstream = smart_playlist
    downstream = smart_playlist(:playlist_rule, excluded_playlist: upstream.target_playlist)

    expect(wave_ids).to eq([[upstream.id], [downstream.id]])
  end

  it "puts everything unrelated in one wave" do
    first = smart_playlist
    second = smart_playlist

    expect(wave_ids).to eq([[first.id, second.id].sort])
  end

  it "excludes smart playlists that are disabled or have no rules" do
    enabled = smart_playlist
    create(:smart_playlist, :with_rules, user: user, is_enabled: false)
    create(:smart_playlist, user: user)

    expect(wave_ids).to eq([[enabled.id]])
  end

  it "promotes a downstream whose upstream is not a candidate" do
    upstream = create(:smart_playlist, :with_rules, user: user, is_enabled: false)
    downstream = smart_playlist(sources: [upstream.target_playlist])

    expect(wave_ids).to eq([[downstream.id]])
  end

  it "ignores another user's graph" do
    mine = smart_playlist
    create(:smart_playlist, :enabled)

    expect(wave_ids).to eq([[mine.id]])
  end

  it "has no waves when nothing is eligible" do
    expect(order.waves).to be_empty
  end

  # Validations make a stored cycle unreachable, so force one the way an
  # insert_all or update_column path could.
  context "with a cycle that bypassed validation" do
    it "emits the remainder as one wave rather than looping" do
      first = smart_playlist
      second = smart_playlist(sources: [first.target_playlist])
      SmartPlaylistSource.where(smart_playlist_id: first.id)
                         .update_all(playlist_id: second.target_playlist_id)

      expect(wave_ids).to eq([[first.id, second.id].sort])
      expect(order).to be_cyclic
    end
  end
end
