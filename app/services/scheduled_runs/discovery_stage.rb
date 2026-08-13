# frozen_string_literal: true

module ScheduledRuns
  class DiscoveryStage
    def initialize(run)
      @run = run
    end

    def start
      user_ids = EligibleUsers.call.pluck(:id)
      run.update!(stage_total: user_ids.size, stage_completed: 0)

      jobs = user_ids.map { |id| ScheduledPlaylistDiscoveryJob.new(scheduled_run_id: run.id, user_id: id) }
      ActiveJob.perform_all_later(jobs)
    end

    def settled?
      run.stage_completed >= run.stage_total
    end

    def abandon!
      outstanding = run.stage_total - run.stage_completed
      run.record_stage_error!(:discovery, "timed out with #{outstanding} playlist fetches unfinished")
    end

    def continue!
      false
    end

    private

    attr_reader :run
  end
end
