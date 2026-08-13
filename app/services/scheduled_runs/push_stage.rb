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
      wave_sessions.active.none?
    end

    def abandon!
      sessions = wave_sessions.active.to_a
      sessions.each { |session| PushFailureHandler.fail_session(session, error_message: TIMEOUT_MESSAGE) }
      run.record_stage_error!("pushes_wave_#{run.push_wave}", "timed out; #{sessions.size} pushes abandoned")
    end

    def advance!
      run.update!(push_wave: run.push_wave + 1, stage_started_at: Time.current)
      return :done if run.current_wave.empty?

      start_wave
      :continue
    end

    private

    attr_reader :run

    def wave_sessions
      run.push_sessions.where(smart_playlist_id: run.current_wave)
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
