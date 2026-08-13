# frozen_string_literal: true

module ScheduledRuns
  class Advancer
    def initialize(run)
      @run = run
    end

    def call
      run.with_lock do
        next unless run.running?
        next expire! if run.expired?

        step
      end
    end

    private

    attr_reader :run

    def step
      stage = Stages.for(run)
      settled = stage.settled?
      return unless settled || run.timed_out?

      stage.abandon! unless settled
      enter_next_stage if stage.advance! == :done
    end

    def enter_next_stage
      next_stage = Stages.after(run.stage)
      return finish! unless next_stage

      run.enter_stage!(next_stage)
      Stages.for(run).start
    end

    def finish!
      run.update!(
        status: run.degraded? ? :completed_with_errors : :completed,
        completed_at: Time.current,
      )
    end

    def expire!
      Stages.for(run).abandon!
      run.record_stage_error!(:hard_cap, "run exceeded #{ScheduledRun::HARD_CAP.inspect}")
      run.update!(status: :completed_with_errors, completed_at: Time.current)
    end
  end
end
