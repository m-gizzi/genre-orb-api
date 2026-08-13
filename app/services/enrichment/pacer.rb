# frozen_string_literal: true

module Enrichment
  # Proactive pacing, not reactive backoff. MusicBrainz caps clients at 1 request per
  # second and does not tell you when you have crossed the line until it 503s, so the
  # limit has to be respected before the fact.
  #
  # A plain in-process sleep is a sufficient *global* limiter only because
  # Enrichment::Lock guarantees one tick per source runs at a time. Without the lock
  # this would be per-worker and three workers would fire three requests a second.
  class Pacer
    def initialize(min_interval)
      @min_interval = min_interval.to_f
      @next_allowed_at = nil
    end

    def wait
      return if min_interval.zero?

      pause = next_allowed_at.to_f - now
      sleep(pause) if next_allowed_at && pause.positive?
      @next_allowed_at = now + min_interval
    end

    private

    attr_reader :min_interval, :next_allowed_at

    # Monotonic, so a clock adjustment mid-tick cannot produce a huge sleep.
    def now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end
end
