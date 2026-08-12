# frozen_string_literal: true

require "rails_helper"

RSpec.describe FanInCounter do
  subject(:session) { create(:push_session, :with_batches, remove_batches: 2) }

  def advance(**extra)
    session.advance_counter!(:completed_remove_batches, :total_remove_batches, **extra)
  end

  it "reports the last unit to exactly one caller" do
    expect(advance).to be(false)
    expect(advance).to be(true)
  end

  it "persists each increment" do
    2.times { advance }

    expect(session.reload.completed_remove_batches).to eq(2)
  end

  it "writes the extra attributes it is given" do
    advance(spotify_snapshot_id: "snap_1")

    expect(session.reload.spotify_snapshot_id).to eq("snap_1")
  end

  it "leaves an existing value alone when the extra attribute is nil" do
    session.update!(spotify_snapshot_id: "snap_1")

    advance(spotify_snapshot_id: nil)

    expect(session.reload.spotify_snapshot_id).to eq("snap_1")
  end

  it "keeps counting past the total rather than raising" do
    3.times { advance }

    expect(session.reload.completed_remove_batches).to eq(3)
  end
end
