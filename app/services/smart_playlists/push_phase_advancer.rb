# frozen_string_literal: true

module SmartPlaylists
  class PushPhaseAdvancer
    def initialize(push_session, adapter:)
      @push_session = push_session
      @adapter = adapter
    end

    def remove_batch_done(snapshot_id)
      return unless advance(:completed_remove_batches, :total_remove_batches, snapshot_id)

      start_add_phase
    end

    def add_batch_done(snapshot_id)
      return unless advance(:completed_add_batches, :total_add_batches, snapshot_id)

      finalize
    end

    def start_add_phase
      slices = PushStrategies.for(push_session).add_slices
      return finalize if slices.empty?

      jobs = slices.map do |spotify_ids|
        PlaylistTrackAdditionJob.new(push_session_id: push_session.id, spotify_ids: spotify_ids)
      end
      ActiveJob.perform_all_later(jobs)
    end

    private

    attr_reader :push_session, :adapter

    def advance(completed_column, total_column, snapshot_id)
      push_session.advance_counter!(completed_column, total_column, spotify_snapshot_id: snapshot_id)
    end

    def finalize
      PushFinalizer.new(push_session, adapter: adapter).call
    end
  end
end
