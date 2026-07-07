# frozen_string_literal: true

module Spotify
  class LibrarySyncInitializer
    Result = Struct.new(:success?, :sync_session, :playlist_session_ids, :skipped_reason, keyword_init: true)

    def initialize(user)
      @user = user
    end

    def call
      playlists = @user.playlists.sync_enabled.available

      if playlists.empty?
        return Result.new(success?: true, skipped_reason: "no playlists to sync")
      end

      session = SyncSession.create!(user: @user, status: :running, started_at: Time.current)

      playlist_sessions = playlists.map do |playlist|
        session.sync_session_playlists.create!(playlist: playlist, status: :pending)
      end

      Result.new(
        success?: true,
        sync_session: session,
        playlist_session_ids: playlist_sessions.map(&:id)
      )
    end
  end
end
