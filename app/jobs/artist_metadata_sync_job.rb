# frozen_string_literal: true

class ArtistMetadataSyncJob < ApplicationJob
  queue_as :sync

  BATCH_SIZE = SpotifyAdapter::ARTIST_BATCH_LIMIT

  def perform(user_id)
    user = User.find(user_id)

    artist_ids = Artist.where(metadata_fetched_at: nil).pluck(:id)

    if artist_ids.empty?
      Rails.logger.info("ArtistMetadataSyncJob: user=#{user_id} no artists to sync")
      return
    end

    total_batches = (artist_ids.size.to_f / BATCH_SIZE).ceil

    session = ArtistMetadataSession.create!(
      user: user,
      status: :running,
      total_batches: total_batches,
      completed_batches: 0,
      started_at: Time.current
    )

    jobs = artist_ids.each_slice(BATCH_SIZE).map do |batch_ids|
      ArtistBatchFetchJob.new(
        session_id: session.id,
        user_id: user_id,
        artist_ids: batch_ids
      )
    end

    ActiveJob.perform_all_later(jobs)

    Rails.logger.info(
      "ArtistMetadataSyncJob: user=#{user_id} session=#{session.id} " \
      "artists=#{artist_ids.size} batches=#{total_batches}"
    )
  end
end
