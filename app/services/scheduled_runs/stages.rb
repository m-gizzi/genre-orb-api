# frozen_string_literal: true

module ScheduledRuns
  # Every stage answers the same four questions, so Advancer never branches on
  # which one is running.
  #
  #   start     — kick off the stage's work
  #   settled?  — nothing in the current unit of work is still in flight
  #   abandon!  — fail what is still in flight and record why
  #   advance!  — :continue if it started another unit of work (only pushes, which
  #               run in waves), :done if the stage is over
  module Stages
    CLASSES = {
      "discovery" => DiscoveryStage,
      "library_sync" => LibrarySyncStage,
      "artist_metadata" => ArtistMetadataStage,
      "pushes" => PushStage,
    }.freeze

    ORDER = CLASSES.keys.freeze

    def self.for(run)
      CLASSES.fetch(run.stage).new(run)
    end

    def self.after(stage)
      ORDER[ORDER.index(stage) + 1]
    end
  end
end
