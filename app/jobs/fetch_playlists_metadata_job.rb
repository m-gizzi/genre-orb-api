# frozen_string_literal: true

class FetchPlaylistsMetadataJob < SpotifyJob
  def perform(user_id)
    user = User.find(user_id)

    if rate_limited?(user.id)
      defer_for_rate_limit(user.id)
      return
    end

    Spotify::PlaylistMetadataFetcher.new(user).call
  end
end
