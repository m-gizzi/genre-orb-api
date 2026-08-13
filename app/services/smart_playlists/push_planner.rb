# frozen_string_literal: true

module SmartPlaylists
  class PushPlanner
    def initialize(push_session, adapter:)
      @push_session = push_session
      @adapter = adapter
    end

    def call
      discard_previous_attempt!
      pin_baseline!

      track_set = PushTrackSet.new(evaluator)
      nothing_to_push = track_set.entries.empty?
      evaluator.record!

      return skip_no_matches! if nothing_to_push

      build_version!(track_set)
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
                           total_add_batches: 0, completed_add_batches: 0, add_phase_started_at: nil,)
      version.destroy!
    end

    def pin_baseline!
      push_session.update!(baseline_version_id: target.current_version_id)
    end

    def skip_no_matches!
      push_session.update!(
        status: :skipped,
        error_message: I18n.t("api.smart_playlists.push_no_matches"),
        completed_at: Time.current,
      )
    end

    def build_version!(track_set)
      ActiveRecord::Base.transaction do
        version = PlaylistVersion.create_for_push!(target)
        PushVersionTrackBuilder.new(version).call(track_set.entries)
        push_session.update!(playlist_version: version)
      end
    end

    def commit_plan(track_set)
      push_session.strategy = chosen_strategy
      strategy = PushStrategies.for(push_session, batches: batches)
      push_session.update!(plan_attributes(track_set, strategy))
      strategy
    end

    def batches
      @batches ||= PushBatches.new(push_session)
    end

    def advancer
      PushPhaseAdvancer.new(push_session)
    end

    def plan_attributes(track_set, strategy)
      {
        match_count: track_set.total_match_count,
        sampled: track_set.sampled?,
        tracks_added: batches.diff.to_add.size,
        tracks_removed: batches.diff.to_remove.size,
        total_remove_batches: strategy.remove_batch_count,
        total_add_batches: strategy.add_slices.size,
      }
    end

    def chosen_strategy
      return :replace unless baseline_trusted?

      diff_batches = PushStrategies::Diff.new(batches).total_batches
      replace_batches = PushStrategies::Replace.new(batches).total_batches
      diff_batches <= replace_batches ? :diff : :replace
    end

    def baseline_trusted?
      known = push_session.baseline_version&.spotify_snapshot_id
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
