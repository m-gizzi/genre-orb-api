# frozen_string_literal: true

require "rails_helper"

RSpec.describe AlbumSerializer do
  let(:album) { create(:album, title: "Reign in Blood", total_tracks: 10) }

  it "reports the saved track count supplied by the caller" do
    result = described_class.new(album, params: { saved_counts: { album.id => 3 } }).serializable_hash

    expect(result).to include("saved_tracks" => 3, "total_tracks" => 10)
  end

  it "reports zero for an album absent from saved_counts" do
    result = described_class.new(album, params: { saved_counts: {} }).serializable_hash

    expect(result["saved_tracks"]).to eq(0)
  end

  it "fails loudly rather than reporting zero when saved_counts is omitted" do
    expect { described_class.new(album).serializable_hash }.to raise_error(KeyError)
  end
end
