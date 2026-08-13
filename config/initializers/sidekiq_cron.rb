# frozen_string_literal: true

return unless Sidekiq.server?

Rails.application.config.after_initialize do
  Sidekiq::Cron::Job.load_from_hash!(
    "scheduled_run_tick" => {
      "cron" => "*/2 * * * *",
      "class" => "ScheduledRunTickJob",
      "queue" => "default",
      "description" => "Starts and advances the nightly scheduled run",
    },
    "musicbrainz_enrichment" => {
      "cron" => "* * * * *",
      "class" => "EnrichmentTickJob",
      "queue" => "enrichment",
      "args" => ["musicbrainz"],
      "description" => "Drips artist genre enrichment from MusicBrainz",
    },
    "lastfm_enrichment" => {
      "cron" => "* * * * *",
      "class" => "EnrichmentTickJob",
      "queue" => "enrichment",
      "args" => ["lastfm"],
      "description" => "Drips artist genre enrichment from Last.fm",
    },
  )
end
