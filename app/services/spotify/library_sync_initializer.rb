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

      session = SyncSession.create!(
        user: user,
        status: :running,
        started_at: Time.current,
        total_playlists: playlists.count,
      )

      playlist_sessions = playlists.map do |playlist|
        session.sync_session_playlists.create!(playlist: playlist, status: :pending)
      end

      Result.new(
        sync_session: session,
        playlist_session_ids: playlist_sessions.map(&:id),
      )
    end
  end
end
