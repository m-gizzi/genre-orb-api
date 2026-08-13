# frozen_string_literal: true

module ScheduledRuns
  class Starter
    include SessionClaim

    # Creating the run and starting its first stage are one transaction, and the
    # run is `running` from the first insert. A stage that fails to start therefore
    # leaves no row behind, so the next tick can retry inside the kickoff window —
    # a run stranded in `pending` would hold the single-active-run index forever
    # and Advancer would refuse to touch it.
    def call
      ScheduledRun.transaction do
        run = claim { create_run }
        next nil unless run

        Stages.for(run).start
        run
      end
    end

    private

    def create_run
      ScheduledRun.create!(
        run_date: ScheduledRun.date_for,
        status: :running,
        stage: :discovery,
        stage_started_at: Time.current,
        started_at: Time.current,
      )
    end
  end
end
