# frozen_string_literal: true

class FetchPlaylistsMetadataJob < ApplicationJob
  queue_as :sync

  def perform(user_id)
    @user = User.find(user_id)
    fetch_playlists
  end

  private

  def fetch_playlists
    Spotify::PlaylistMetadataFetcher.new(@user).call
  end
end
