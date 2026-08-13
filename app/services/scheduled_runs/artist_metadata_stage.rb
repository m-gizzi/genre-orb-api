# frozen_string_literal: true

module ScheduledRuns
  class ArtistMetadataStage
    TIMEOUT_MESSAGE = "Abandoned by the scheduled run after its stage timeout"

    def initialize(run)
      @run = run
    end

    # `no_artists` is a healthy night, not a fault — recording it would push the run
    # to completed_with_errors for having nothing to do. Anything else means a
    # session stranded by an earlier run is holding the index.
    EXPECTED_OUTCOMES = %i[started no_artists].freeze

    def start
      outcome = Spotify::GlobalArtistMetadataInitializer.new(scheduled_run: run).call.outcome
      return if outcome.in?(EXPECTED_OUTCOMES)

      run.record_stage_error!(:artist_metadata_skipped, "not started (#{outcome})")
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
