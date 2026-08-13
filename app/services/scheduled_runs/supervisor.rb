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
      return false if ScheduledRun.exists?(run_date: ScheduledRun.date_for)

      opens_at = ScheduledRun.opens_at
      Time.current.between?(opens_at, opens_at + ScheduledRun::KICKOFF_WINDOW)
    end
  end
end
