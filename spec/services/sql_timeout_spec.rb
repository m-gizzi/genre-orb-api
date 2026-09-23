# frozen_string_literal: true

require "rails_helper"

RSpec.describe SqlTimeout do
  def setting(name)
    ActiveRecord::Base.connection.select_value("SHOW #{name}")
  end

  describe ".guard" do
    it "caps how long a statement inside the block may run" do
      expect(described_class.guard(statement: 5_000) { setting("statement_timeout") }).to eq("5s")
    end

    it "caps how long a statement waits for a lock" do
      expect(described_class.guard(lock: 5_000) { setting("lock_timeout") }).to eq("5s")
    end

    it "sets both when both are given" do
      inside = described_class.guard(statement: 30_000, lock: 5_000) do
        [setting("statement_timeout"), setting("lock_timeout")]
      end

      expect(inside).to eq(%w[30s 5s])
    end

    it "leaves a setting alone when it is not given" do
      expect(described_class.guard(statement: 5_000) { setting("lock_timeout") }).to eq("0")
    end

    it "accepts an interval string as well as milliseconds" do
      expect(described_class.guard(statement: "5s") { setting("statement_timeout") }).to eq("5s")
    end

    it "returns the block's value" do
      expect(described_class.guard(statement: 5_000) { :result }).to eq(:result)
    end

    it "extends the cap to an enclosing transaction" do
      ActiveRecord::Base.transaction do
        described_class.guard(statement: 5_000) { nil }

        expect(setting("statement_timeout")).to eq("5s")
      end
    end
  end

  describe ".apply" do
    it "sets the timeouts on a transaction the caller already owns" do
      ActiveRecord::Base.transaction do
        described_class.apply(statement: 30_000, lock: 5_000)

        expect(setting("statement_timeout")).to eq("30s")
        expect(setting("lock_timeout")).to eq("5s")
      end
    end

    it "touches nothing when given neither" do
      ActiveRecord::Base.transaction do
        described_class.apply

        expect(setting("statement_timeout")).to eq("0")
        expect(setting("lock_timeout")).to eq("0")
      end
    end
  end
end
