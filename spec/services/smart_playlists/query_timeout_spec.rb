# frozen_string_literal: true

require "rails_helper"

RSpec.describe SmartPlaylists::QueryTimeout do
  def statement_timeout
    ActiveRecord::Base.connection.select_value("SHOW statement_timeout")
  end

  it "caps how long a query inside the block may run" do
    inside = described_class.guard { statement_timeout }

    expect(inside).to eq("#{described_class::TIMEOUT_MS / 1000}s")
  end

  it "returns the block's value" do
    expect(described_class.guard { :result }).to eq(:result)
  end

  it "extends the cap to an enclosing transaction" do
    ActiveRecord::Base.transaction do
      described_class.guard { nil }

      expect(statement_timeout).to eq("#{described_class::TIMEOUT_MS / 1000}s")
    end
  end
end
