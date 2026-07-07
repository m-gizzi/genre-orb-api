# frozen_string_literal: true

class ArtistBatchFetchJob < SpotifyJob
  sidekiq_retries_exhausted do |job, exception|
    args = job["args"].first
    session = ArtistMetadataSession.find_by(id: args["session_id"])
    return unless session

    session.update!(
      status: :failed,
      error_message: "Batch fetch failed after retries: #{exception.message}",
      completed_at: Time.current
    )
  end

  def perform(session_id:, user_id:, artist_ids:)
    return if defer_if_rate_limited(user_id)

    session = ArtistMetadataSession.find(session_id)
    return if session.failed?

    user = User.find(user_id)
    adapter = SpotifyAdapter.new(user.spotify_connection)

    spotify_ids = Artist.where(id: artist_ids).pluck(:spotify_id)
    return if spotify_ids.empty?

    response = adapter.artists(spotify_ids)
    Spotify::ArtistMetadataUpserter.new(response).call

    if session.batch_completed!
      session.update!(status: :completed, completed_at: Time.current)
    end
  end
end
