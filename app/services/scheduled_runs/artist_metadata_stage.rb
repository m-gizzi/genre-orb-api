# frozen_string_literal: true

module ScheduledRuns
  class ArtistMetadataStage
    TIMEOUT_MESSAGE = "Abandoned by the scheduled run after its stage timeout"

    def initialize(run)
      @run = run
    end

    def start
      Spotify::GlobalArtistMetadataInitializer.new(scheduled_run: run).call
    end

    def settled?
      run.artist_metadata_sessions.active.none?
    end

    def abandon!
      sessions = run.artist_metadata_sessions.active.to_a
      sessions.each { |session| session.fail!(error_message: TIMEOUT_MESSAGE) }
      run.record_stage_error!(:artist_metadata, "timed out; #{sessions.size} sessions abandoned")
    end

    def continue!
      false
    end

    private

    attr_reader :run
  end
end
