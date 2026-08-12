# frozen_string_literal: true

class PlaylistTracksReplaceJob < PushJob
  sidekiq_retries_exhausted do |job, exception|
    fail_push(job, exception, "Replacing the playlist failed after retries")
  end

  def perform(push_session_id:, spotify_ids:)
    perform_push(push_session_id) do |adapter, spotify_playlist_id|
      adapter.replace_playlist_tracks(spotify_playlist_id, spotify_ids)
    end
  end

  private

  def advance(push_session, snapshot_id)
    SmartPlaylists::PushPhaseAdvancer.new(push_session).remove_batch_done(snapshot_id)
  end
end
