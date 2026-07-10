# frozen_string_literal: true

module Spotify
  class LibrarySyncInitializer
    Result = Struct.new(:sync_session, :playlist_session_ids, :skipped_reason, keyword_init: true)

    attr_reader :user

    def initialize(user)
      @user = user
    end

    def call
      playlists = user.playlists.sync_enabled.available

      return Result.new(skipped_reason: "no playlists to sync") if playlists.empty?

      session = create_session(playlists.count)
      return Result.new(skipped_reason: "sync already in progress") unless session

      playlist_sessions = playlists.map do |playlist|
        session.sync_session_playlists.create!(playlist: playlist, status: :pending)
      end

      Result.new(
        sync_session: session,
        playlist_session_ids: playlist_sessions.map(&:id),
      )
    end

    private

    def create_session(total_playlists)
      SyncSession.create!(
        user: user,
        status: :running,
        started_at: Time.current,
        total_playlists: total_playlists,
      )
    rescue ActiveRecord::RecordNotUnique
      nil
    end
  end
end
