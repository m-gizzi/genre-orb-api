# frozen_string_literal: true

module ScheduledRuns
  class Starter
    def call
      run = create_run
      return nil unless run

      Stages.for(run).start
      run.update!(status: :running)
      run
    end

    private

    def create_run
      ScheduledRun.create!(
        run_date: Date.current,
        status: :pending,
        stage: :discovery,
        stage_started_at: Time.current,
        started_at: Time.current,
      )
    rescue ActiveRecord::RecordNotUnique
      nil
    end
  end
end
