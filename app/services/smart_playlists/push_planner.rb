# frozen_string_literal: true

module SmartPlaylists
  class PushPlanner
    def initialize(push_session, adapter:)
      @push_session = push_session
      @adapter = adapter
    end

    def call
      discard_previous_attempt!

      track_set = PushTrackSet.new(evaluator)
      nothing_to_push = track_set.entries.empty?
      evaluator.record!

      return fail_no_matches! if nothing_to_push

      strategy = commit_plan(track_set)
      start_remove_phase(strategy)
    end

    private

    attr_reader :push_session, :adapter

    def evaluator
      @evaluator ||= Evaluator.new(smart_playlist)
    end

    def smart_playlist
      @smart_playlist ||= push_session.smart_playlist
    end

    def target
      @target ||= smart_playlist.target_playlist
    end

    def discard_previous_attempt!
      version = push_session.playlist_version
      return unless version

      push_session.update!(playlist_version: nil, total_remove_batches: 0, completed_remove_batches: 0,
                           total_add_batches: 0, completed_add_batches: 0,)
      version.destroy!
    end

    def fail_no_matches!
      PushFailureHandler.fail_session(push_session, error_message: I18n.t("api.smart_playlists.push_no_matches"))
    end

    def commit_plan(track_set)
      ActiveRecord::Base.transaction do
        build_version!(track_set)
        push_session.update!(strategy: chosen_strategy)

        PushStrategies.for(push_session, batches: batches).tap do |strategy|
          push_session.update!(plan_attributes(track_set, strategy))
        end
      end
    end

    def build_version!(track_set)
      version = PlaylistVersion.create_for_push!(target)
      PushVersionTrackBuilder.new(version).call(track_set.entries)
      push_session.update!(playlist_version: version)
    end

    def batches
      @batches ||= PushBatches.new(push_session)
    end

    def advancer
      PushPhaseAdvancer.new(push_session, adapter: adapter)
    end

    def plan_attributes(track_set, strategy)
      {
        match_count: track_set.total_match_count,
        sampled: track_set.sampled?,
        tracks_added: strategy.tracks_added,
        tracks_removed: strategy.tracks_removed,
        total_remove_batches: strategy.remove_batch_count,
        total_add_batches: strategy.add_slices.size,
      }
    end

    def chosen_strategy
      return :replace unless baseline_trusted?

      batches.diff_cost <= batches.replace_cost ? :diff : :replace
    end

    def baseline_trusted?
      known = target.current_version&.spotify_snapshot_id
      return false if known.blank?

      adapter.playlist_snapshot_id(target.spotify_id) == known
    end

    def start_remove_phase(strategy)
      return start_replace_phase(strategy) if strategy.clear?

      slices = strategy.remove_slices
      return advancer.start_add_phase if slices.empty?

      jobs = slices.map do |spotify_ids|
        PlaylistTrackRemovalJob.new(push_session_id: push_session.id, spotify_ids: spotify_ids)
      end
      ActiveJob.perform_all_later(jobs)
    end

    def start_replace_phase(strategy)
      PlaylistTracksReplaceJob.perform_later(
        push_session_id: push_session.id,
        spotify_ids: strategy.seed_slice,
      )
    end
  end
end
