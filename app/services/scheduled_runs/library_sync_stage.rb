# frozen_string_literal: true

module ScheduledRuns
  class LibrarySyncStage
    TIMEOUT_MESSAGE = "Abandoned by the scheduled run after its stage timeout"

    def initialize(run)
      @run = run
    end

    def start
      skipped = 0
      EligibleUsers.call.find_each do |user|
        skipped += 1 unless Spotify::LibrarySyncInitializer.new(user, scheduled_run: run).call.started?
      end

      run.record_stage_error!(:library_sync_skipped, "#{skipped} users skipped") if skipped.positive?
    end

    def settled?
      run.sync_sessions.active.none?
    end

    def abandon!
      sessions = run.sync_sessions.active.to_a
      sessions.each { |session| SyncFailureHandler.fail_session(session, error_message: TIMEOUT_MESSAGE) }
      run.record_stage_error!(:library_sync, "timed out; #{sessions.size} sessions abandoned")
    end

    def advance!
      :done
    end

    private

    attr_reader :run
  end
end
