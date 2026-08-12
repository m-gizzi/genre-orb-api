# frozen_string_literal: true

module SmartPlaylists
  class PushInitializer
    Result = Struct.new(:outcome, :session, keyword_init: true) { include StartableResult }

    def initialize(smart_playlist)
      @smart_playlist = smart_playlist
    end

    def call
      blocked = blocking_outcome
      return Result.new(outcome: blocked) if blocked

      start_push
    end

    private

    attr_reader :smart_playlist

    def blocking_outcome
      return :spotify_not_connected unless smart_playlist.user.spotify_connected?
      return :not_ready unless smart_playlist.ready?
      return :already_in_progress if smart_playlist.push_sessions.active.exists?

      nil
    end

    def start_push
      session = create_session
      return Result.new(outcome: :already_in_progress) unless session

      PushPlanJob.perform_later(push_session_id: session.id)
      Result.new(outcome: :started, session: session)
    end

    def create_session
      PushSession.create!(smart_playlist: smart_playlist, status: :running, started_at: Time.current)
    rescue ActiveRecord::RecordNotUnique
      nil
    end
  end
end
