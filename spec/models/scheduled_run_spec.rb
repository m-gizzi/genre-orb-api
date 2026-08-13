# frozen_string_literal: true

require "rails_helper"

RSpec.describe ScheduledRun do
  describe "uniqueness at the database level" do
    it "rejects a second run for the same day" do
      create(:scheduled_run, :completed, run_date: Date.current)

      expect { create(:scheduled_run, :completed, run_date: Date.current) }
        .to raise_error(ActiveRecord::RecordNotUnique)
    end

    it "rejects a second active run even on a different day" do
      create(:scheduled_run, run_date: Date.current - 1)

      expect { create(:scheduled_run, run_date: Date.current) }
        .to raise_error(ActiveRecord::RecordNotUnique)
    end

    it "allows a new run once the previous one is terminal" do
      create(:scheduled_run, :completed, run_date: Date.current - 1)

      expect { create(:scheduled_run, run_date: Date.current) }.not_to raise_error
    end
  end

  describe ".next_run_at" do
    it "returns today's slot when it is still ahead" do
      travel_to Time.utc(2026, 8, 13, 1, 0, 0) do
        expect(described_class.next_run_at).to eq(Time.utc(2026, 8, 13, described_class::RUN_HOUR))
      end
    end

    it "rolls to tomorrow once the slot has passed" do
      travel_to Time.utc(2026, 8, 13, 12, 0, 0) do
        expect(described_class.next_run_at).to eq(Time.utc(2026, 8, 14, described_class::RUN_HOUR))
      end
    end
  end

  describe "#timed_out?" do
    let!(:run) { create(:scheduled_run, :library_sync, stage_started_at: Time.current) }

    it "is false inside the stage's budget" do
      travel_to(1.hour.from_now) { expect(run).not_to be_timed_out }
    end

    it "is true past it" do
      travel_to(3.hours.from_now) { expect(run).to be_timed_out }
    end

    it "uses the stage's own budget" do
      run.update!(stage: :pushes)

      travel_to(1.hour.from_now) { expect(run).to be_timed_out }
    end
  end

  describe "#expired?" do
    it "is true only past the hard cap" do
      run = create(:scheduled_run, started_at: Time.current)

      travel_to(described_class::HARD_CAP.from_now - 1.minute) { expect(run).not_to be_expired }
      travel_to(described_class::HARD_CAP.from_now + 1.minute) { expect(run).to be_expired }
    end
  end

  describe "#discovery_completed!" do
    let(:run) { create(:scheduled_run, stage_total: 2, stage_completed: 0) }

    it "reports the fan-in completing on the last increment" do
      expect(run.discovery_completed!).to be(false)
      expect(run.discovery_completed!).to be(true)
    end

    it "ignores a job that lands after the stage moved on" do
      run.enter_stage!(:library_sync)

      expect(run.discovery_completed!).to be(false)
      expect(run.reload.stage_completed).to eq(0)
    end
  end

  describe "#record_stage_error! and #degraded?" do
    it "accumulates keyed reasons" do
      run = create(:scheduled_run)

      expect(run).not_to be_degraded

      run.record_stage_error!(:discovery, "timed out")
      run.record_stage_error!(:library_sync, "also timed out")

      expect(run.stage_errors).to eq("discovery" => "timed out", "library_sync" => "also timed out")
      expect(run).to be_degraded
    end
  end

  describe "#current_wave" do
    it "reads the wave the cursor points at" do
      run = create(:scheduled_run, :pushes, push_plan: [[1, 2], [3]], push_wave: 1)

      expect(run.current_wave).to eq([3])
    end

    it "is empty once the cursor runs off the end" do
      run = create(:scheduled_run, :pushes, push_plan: [[1]], push_wave: 1)

      expect(run.current_wave).to eq([])
    end
  end
end
