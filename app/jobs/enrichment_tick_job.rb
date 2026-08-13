# frozen_string_literal: true

# Deliberately not a SpotifyJob: it makes no Spotify calls, and inheriting that
# around_perform would defer these ticks whenever Spotify happens to be throttling us.
#
# retry: false with an internal rescue, for the same reason as ScheduledRunTickJob — a
# poisoned tick must not take the drip down when the next one is a minute away.
class EnrichmentTickJob < ApplicationJob
  queue_as :enrichment

  sidekiq_options retry: false

  TICK_BUDGET = 20.seconds
  # Comfortably longer than TICK_BUDGET so a worker killed mid-tick still frees the
  # lock, without a live tick ever losing it.
  LOCK_TTL = 90

  def perform(source)
    outcome = Enrichment::Lock.acquire(source, ttl: LOCK_TTL) do
      result = Enrichment::Drip.for(strategy_for(source), deadline: TICK_BUDGET.from_now).call
      Rails.logger.info("EnrichmentTickJob(#{source}): #{result}")
    end

    Rails.logger.info("EnrichmentTickJob(#{source}) skipped: previous tick still running") if outcome == :busy
  rescue StandardError => e
    Rails.logger.error("EnrichmentTickJob(#{source}) failed (#{e.class}): #{e.message}")
  end

  private

  def strategy_for(source)
    case source.to_s
    when "musicbrainz" then Enrichment::MusicbrainzStrategy.new
    when "lastfm" then Enrichment::LastfmStrategy.new
    else raise ArgumentError, "Unknown enrichment source: #{source}"
    end
  end
end
