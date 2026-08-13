# frozen_string_literal: true

module ScheduledRuns
  class PushStage
    TIMEOUT_MESSAGE = "Abandoned by the scheduled run after its wave timeout"

    def initialize(run)
      @run = run
    end

    def start
      run.update!(push_plan: build_plan, push_wave: 0)
      start_wave
    end

    def settled?
      wave_pushes.none?
    end

    def abandon!
      sessions = our_wave_pushes.to_a
      sessions.each { |session| PushFailureHandler.fail_session(session, error_message: TIMEOUT_MESSAGE) }
      run.record_stage_error!("pushes_wave_#{run.push_wave}", timeout_reason(sessions.size))
    end

    def advance!
      run.update!(push_wave: run.push_wave + 1, stage_started_at: Time.current)
      return :done if run.current_wave.empty?

      start_wave
      :continue
    end

    private

    attr_reader :run

    # Any active push for a wave member holds the wave open, not just ours: a
    # playlist whose push we could not start because one was already running still
    # has to land before the next wave reads its target.
    def wave_pushes
      PushSession.active.where(smart_playlist_id: run.current_wave)
    end

    # Abandoning is narrower than waiting — a push someone started by hand is not
    # ours to fail, so it only gets named in the stage error.
    def our_wave_pushes
      run.push_sessions.active.where(smart_playlist_id: run.current_wave)
    end

    def timeout_reason(abandoned)
      reason = "timed out; #{abandoned} pushes abandoned"
      stragglers = wave_pushes.count
      return reason if stragglers.zero?

      "#{reason}; #{stragglers} started outside this run still active"
    end

    # Users are independent graphs, so wave k of one lines up with wave k of any
    # other. Persisted, so rules edited mid-run cannot reshape the plan.
    def build_plan
      plans = EligibleUsers.call.map { |user| SmartPlaylists::PushOrder.new(user).waves }
      depth = plans.map(&:size).max.to_i

      Array.new(depth) { |index| wave_at(plans, index) }.reject(&:empty?)
    end

    def wave_at(plans, index)
      plans.filter_map { |waves| waves[index] }.flatten.map(&:id)
    end

    def start_wave
      skipped = 0
      SmartPlaylist.where(id: run.current_wave).find_each do |smart_playlist|
        skipped += 1 unless SmartPlaylists::PushInitializer.new(smart_playlist, scheduled_run: run).call.started?
      end

      return if skipped.zero?

      run.record_stage_error!("pushes_wave_#{run.push_wave}_skipped", "#{skipped} pushes skipped")
    end
  end
end
