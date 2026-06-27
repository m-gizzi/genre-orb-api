# frozen_string_literal: true

# Sidekiq Cron scheduled jobs
# See: https://github.com/sidekiq-cron/sidekiq-cron

# Jobs will be added in later phases:
# - SyncSchedulerJob: Check which users need syncing
# - SmartPlaylistEvaluationJob: Evaluate smart playlists
# - PlaylistSnapshotJob: Create daily playlist snapshots

# Example format:
# Sidekiq::Cron::Job.create(
#   name: "Sync Scheduler - every minute",
#   cron: "* * * * *",
#   class: "SyncSchedulerJob"
# )
