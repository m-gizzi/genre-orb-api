# frozen_string_literal: true

module Spotify
  class ArtistMetadataSyncInitializer
    BATCH_SIZE = SpotifyAdapter::ARTIST_BATCH_LIMIT

    Result = Struct.new(:outcome, :session, :batches, keyword_init: true) do
      def started?
        outcome == :started
      end
    end

    attr_reader :user, :sync_all

    def initialize(user, sync_all: false)
      @user = user
      @sync_all = sync_all
    end

    def call
      blocked = blocking_outcome
      return Result.new(outcome: blocked) if blocked

      start_sync
    end

    private

    def blocking_outcome
      return :spotify_not_connected unless user.spotify_connected?
      return :already_in_progress if user.artist_metadata_sessions.active.exists?
      return :no_artists if artist_ids.empty?

      nil
    end

    def start_sync
      batches = artist_ids.each_slice(BATCH_SIZE).to_a
      session = create_session(batches.size)
      return Result.new(outcome: :already_in_progress) unless session

      enqueue_batch_jobs(session, batches)
      Result.new(outcome: :started, session: session, batches: batches)
    end

    def artist_ids
      @artist_ids ||= fetch_artist_ids
    end

    def fetch_artist_ids
      scope = sync_all ? user.library_artists : user.library_artists.where(metadata_fetched_at: nil)
      scope.pluck(:id)
    end

    def create_session(total_batches)
      ArtistMetadataSession.create!(
        user: user,
        status: :running,
        total_batches: total_batches,
        completed_batches: 0,
        started_at: Time.current,
      )
    rescue ActiveRecord::RecordNotUnique
      nil
    end

    def enqueue_batch_jobs(session, batches)
      jobs = batches.map do |batch_ids|
        ArtistBatchFetchJob.new(session_id: session.id, user_id: user.id, artist_ids: batch_ids)
      end
      ActiveJob.perform_all_later(jobs)
    end
  end
end
