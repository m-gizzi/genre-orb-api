# frozen_string_literal: true

class ArtistMetadataSyncJob < ApplicationJob
  queue_as :sync

  def perform(user_id, sync_all: false)
    @user_id = user_id
    @sync_all = sync_all

    user = User.find(user_id)
    @result = Spotify::ArtistMetadataSyncInitializer.new(user, sync_all: sync_all).call

    if @result.skipped_reason
      Rails.logger.info("ArtistMetadataSyncJob: user=#{user_id} #{@result.skipped_reason} (sync_all=#{sync_all})")
      return
    end

    enqueue_batch_jobs
    log_success
  end

  private

  def enqueue_batch_jobs
    jobs = @result.batches.map do |batch_ids|
      ArtistBatchFetchJob.new(session_id: @result.session.id, user_id: @user_id, artist_ids: batch_ids)
    end
    ActiveJob.perform_all_later(jobs)
  end

  def log_success
    Rails.logger.info(
      "ArtistMetadataSyncJob: user=#{@user_id} session=#{@result.session.id} " \
      "artists=#{@result.batches.flatten.size} batches=#{@result.batches.size} sync_all=#{@sync_all}",
    )
  end
end
