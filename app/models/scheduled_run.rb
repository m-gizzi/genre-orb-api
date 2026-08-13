# frozen_string_literal: true

class ScheduledRun < ApplicationRecord
  include Sessionable

  RUN_HOUR = 3
  KICKOFF_WINDOW = 3.hours
  HARD_CAP = 6.hours

  # `pushes` is per wave, not for the whole stage.
  STAGE_TIMEOUTS = {
    "discovery" => 45.minutes,
    "library_sync" => 2.hours,
    "artist_metadata" => 90.minutes,
    "pushes" => 30.minutes,
  }.freeze

  has_many :sync_sessions, dependent: :nullify, inverse_of: :scheduled_run
  has_many :artist_metadata_sessions, dependent: :nullify, inverse_of: :scheduled_run
  has_many :push_sessions, dependent: :nullify, inverse_of: :scheduled_run

  # `failed` is here only because Sessionable#fail! needs it. A run always lands
  # on completed or completed_with_errors, the hard cap included.
  enum :status, {
    pending: 0,
    running: 1,
    completed: 2,
    failed: 3,
    completed_with_errors: 4,
  }

  enum :stage, {
    discovery: 0,
    library_sync: 1,
    artist_metadata: 2,
    pushes: 3,
  }, prefix: true

  def self.next_run_at(from: Time.current)
    today = opens_at(from: from)
    today.after?(from) ? today : today + 1.day
  end

  def self.opens_at(from: Time.current)
    from.utc.change(hour: RUN_HOUR, min: 0, sec: 0)
  end

  # The day a run belongs to, read off the same UTC clock the kickoff window uses.
  # Date.current would follow Time.zone, and a local date that rolls over mid-window
  # lets a second run start for the "next" day.
  def self.date_for(from: Time.current)
    from.utc.to_date
  end

  def timed_out?
    stage_started_at.present? && (stage_started_at + STAGE_TIMEOUTS.fetch(stage)).past?
  end

  def expired?
    started_at.present? && (started_at + HARD_CAP).past?
  end

  def degraded?
    stage_errors.any?
  end

  def progress
    total = STAGE_TIMEOUTS.size
    completed = active? ? stages.index(stage) : total
    { total: total, completed: completed, percent: completed * 100 / total }
  end

  def current_wave
    push_plan[push_wave] || []
  end

  def enter_stage!(next_stage)
    update!(stage: next_stage, stage_started_at: Time.current, stage_total: 0, stage_completed: 0)
  end

  def record_stage_error!(key, message)
    update!(stage_errors: stage_errors.merge(key.to_s => message))
  end

  # Only counts while the run is still in discovery: a rate-limit deferral can
  # land a discovery job after the stage moved on, and it must not credit the
  # stage that is running now.
  def discovery_completed!
    with_lock do
      return false unless stage_discovery?

      self.stage_completed += 1
      save!
      stage_completed >= stage_total
    end
  end

  private

  def stages
    STAGE_TIMEOUTS.keys
  end
end
