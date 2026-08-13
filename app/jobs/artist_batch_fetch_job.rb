# frozen_string_literal: true

class ArtistBatchFetchJob < SpotifyJob
  queue_as :metadata

  sidekiq_retries_exhausted do |job, exception|
    abandon(perform_arguments(job).first, exception)
  end

  def self.abandon(arguments, exception)
    session = ArtistMetadataSession.find_by(id: arguments.to_h[:session_id])
    return unless session

    session.fail!(error_message: "Batch fetch failed after retries: #{exception.message}")
  end

  def perform(session_id:, artist_ids:, user_id: nil)
    if rate_limited?(user_id)
      defer_for_rate_limit(user_id)
      return
    end

    session = ArtistMetadataSession.find(session_id)

    Spotify::ArtistBatchProcessor.new(session, artist_ids: artist_ids, adapter: SpotifyAdapter::Catalog.app).call
  end
end
