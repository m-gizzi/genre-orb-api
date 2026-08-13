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
      global_sessions.none?
    end

    def abandon!
      sessions = global_sessions.to_a
      sessions.each { |session| session.fail!(error_message: TIMEOUT_MESSAGE) }
      run.record_stage_error!(:artist_metadata, "timed out; #{sessions.size} sessions abandoned")
    end

    def advance!
      :done
    end

    private

    attr_reader :run

    def global_sessions
      ArtistMetadataSession.global.active
    end
  end
end
