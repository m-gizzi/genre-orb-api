# frozen_string_literal: true

class FetchPlaylistsMetadataJob < ApplicationJob
  queue_as :sync

  def perform(user_id)
    user = User.find(user_id)
    Spotify::PlaylistMetadataFetcher.new(user).call
  end
end
