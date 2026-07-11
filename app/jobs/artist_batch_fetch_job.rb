# frozen_string_literal: true

class ArtistBatchFetchJob < SpotifyJob
  queue_as :metadata

  sidekiq_retries_exhausted do |job, exception|
    args = perform_arguments(job).first || {}
    session = ArtistMetadataSession.find_by(id: args[:session_id])
    next unless session

    session.update!(
      status: :failed,
      error_message: "Batch fetch failed after retries: #{exception.message}",
      completed_at: Time.current,
    )
  end

  def perform(session_id:, user_id:, artist_ids:)
    if rate_limited?(user_id)
      defer_for_rate_limit(user_id)
      return
    end

    session = ArtistMetadataSession.find(session_id)
    user = User.find(user_id)
    adapter = SpotifyAdapter.new(user.spotify_connection)

    Spotify::ArtistBatchProcessor.new(session, artist_ids: artist_ids, adapter: adapter).call
  end
end
