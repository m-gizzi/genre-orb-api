# frozen_string_literal: true

require "rails_helper"

RSpec.describe Track do
  describe ".for_album" do
    it "returns only the tracks on the given album" do
      album = create(:album)
      track = create(:track, album: album)
      create(:track)

      expect(described_class.for_album(album)).to contain_exactly(track)
    end
  end

  describe ".counts_by_album" do
    it "returns distinct track counts keyed by album_id" do
      populated = create(:album)
      single = create(:album)
      create_list(:track, 2, album: populated)
      create(:track, album: single)

      expect(described_class.counts_by_album([populated.id, single.id]))
        .to eq(populated.id => 2, single.id => 1)
    end
  end
end
