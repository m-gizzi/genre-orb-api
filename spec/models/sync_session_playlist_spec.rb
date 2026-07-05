# frozen_string_literal: true

require "rails_helper"

RSpec.describe SyncSessionPlaylist do
  describe "#page_completed!" do
    let(:ssp) do
      create(:sync_session_playlist, total_pages: 3, completed_pages: 0)
    end

    it "increments completed_pages" do
      ssp.page_completed!
      expect(ssp.reload.completed_pages).to eq(1)
    end

    it "returns false when more pages remain" do
      result = ssp.page_completed!
      expect(result).to be(false)
    end

    it "returns true when all pages are complete" do
      ssp.update!(completed_pages: 2)
      result = ssp.page_completed!
      expect(result).to be(true)
    end

    it "handles concurrent calls safely" do
      threads = 3.times.map do
        Thread.new { ssp.page_completed! }
      end
      threads.each(&:join)

      expect(ssp.reload.completed_pages).to eq(3)
    end
  end
end
