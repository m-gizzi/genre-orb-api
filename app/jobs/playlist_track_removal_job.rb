# frozen_string_literal: true

class PlaylistTrackRemovalJob < PushJob
  sidekiq_retries_exhausted do |job, exception|
    abandon(perform_arguments(job).first, exception)
  end

  def self.failure_message
    "Removing tracks failed after retries"
  end

  def perform(push_session_id:, spotify_ids:)
    perform_push(push_session_id) do |adapter, spotify_playlist_id|
      adapter.remove_tracks_from_playlist(spotify_playlist_id, spotify_ids)
    end
  end

  private

  def advance(push_session, snapshot_id)
    SmartPlaylists::PushPhaseAdvancer.new(push_session).remove_batch_done(snapshot_id)
  end
end
