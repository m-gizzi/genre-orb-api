# frozen_string_literal: true

module SmartPlaylists
  class PushPhaseAdvancer
    def initialize(push_session)
      @push_session = push_session
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
      return unless push_session.playlist_version_id

      push_session.with_claimed_add_phase do
        slices = PushStrategies.for(push_session).add_slices
        # Committed here rather than at plan time so the total can never disagree
        # with the batches actually enqueued.
        push_session.update!(total_add_batches: slices.size)
        slices.empty? ? finalize : enqueue_add_batches(slices)
      end
    end

    private

    attr_reader :push_session

    def enqueue_add_batches(slices)
      jobs = slices.map do |spotify_ids|
        PlaylistTrackAdditionJob.new(push_session_id: push_session.id, spotify_ids: spotify_ids)
      end
      ActiveJob.perform_all_later(jobs)
    end

    def advance(completed_column, total_column, snapshot_id)
      push_session.advance_counter!(completed_column, total_column, spotify_snapshot_id: snapshot_id)
    end

    def finalize
      PushFinalizer.new(push_session).call
    end
  end
end
