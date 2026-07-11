# frozen_string_literal: true

module Spotify
  class LibrarySyncInitializer
    Result = Struct.new(:outcome, :sync_session, :playlist_session_ids, keyword_init: true) do
      def started?
        outcome == :started
      end
    end

    attr_reader :user

    def initialize(user)
      @user = user
    end

    def call
      blocked = blocking_outcome
      return Result.new(outcome: blocked) if blocked

      start_sync
    end

    private

    def blocking_outcome
      return :spotify_not_connected unless user.spotify_connected?
      return :already_in_progress if user.sync_sessions.active.exists?
      return :no_playlists if syncable_playlists.empty?

      nil
    end

    def start_sync
      result = create_sync(syncable_playlists)
      return Result.new(outcome: :already_in_progress) unless result

      enqueue_playlist_setup_jobs(result.playlist_session_ids)
      result
    end

    def syncable_playlists
      @syncable_playlists ||= user.playlists.sync_enabled.available
    end

    def create_sync(playlists)
      ActiveRecord::Base.transaction do
        session = SyncSession.create!(
          user: user,
          status: :running,
          started_at: Time.current,
          total_playlists: playlists.count,
        )
        ids = playlists.map do |playlist|
          session.sync_session_playlists.create!(playlist: playlist, status: :pending).id
        end
        Result.new(outcome: :started, sync_session: session, playlist_session_ids: ids)
      end
    rescue ActiveRecord::RecordNotUnique
      nil
    end

    def enqueue_playlist_setup_jobs(playlist_session_ids)
      jobs = playlist_session_ids.map { |id| PlaylistSyncSetupJob.new(id) }
      ActiveJob.perform_all_later(jobs)
    end
  end
end
