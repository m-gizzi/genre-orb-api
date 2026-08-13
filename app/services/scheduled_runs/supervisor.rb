# frozen_string_literal: true

module ScheduledRuns
  class Supervisor
    def call
      run = ScheduledRun.active.first
      return Advancer.new(run).call if run

      Starter.new.call if kickoff_due?
    end

    private

    def kickoff_due?
      return false if ScheduledRun.exists?(run_date: Date.current)

      opens_at = Time.current.utc.change(hour: ScheduledRun::RUN_HOUR, min: 0, sec: 0)
      Time.current.between?(opens_at, opens_at + ScheduledRun::KICKOFF_WINDOW)
    end
  end
end
