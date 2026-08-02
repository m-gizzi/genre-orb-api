# frozen_string_literal: true

class SpotifyAdapter
  ARTIST_BATCH_LIMIT = 50

  def initialize(service_connection)
    @client = Spotify::Client.new(service_connection)
  end

  def user_profile
    client.get("me")
  end

  def verify_connection
    user_profile
    true
  rescue Spotify::AuthenticationError
    false
  end

  def playlists(limit: 50, offset: 0)
    client.get("me/playlists", params: { limit: limit, offset: offset })
  end

  def playlist(playlist_id)
    client.get("playlists/#{playlist_id}")
  end

  def playlist_tracks(playlist_id, limit: 100, offset: 0)
    client.get("playlists/#{playlist_id}/tracks", params: { limit: limit, offset: offset })
  end

  def liked_songs(limit: 50, offset: 0)
    client.get("me/tracks", params: { limit: limit, offset: offset })
  end

  def create_playlist(spotify_user_id, name:, description: nil)
    client.post("users/#{spotify_user_id}/playlists",
                body: { name: name, description: description }.compact,)
  end

  def update_playlist_details(playlist_id, attributes)
    client.put("playlists/#{playlist_id}", body: attributes)
  end

  def artists(spotify_ids)
    if spotify_ids.size > ARTIST_BATCH_LIMIT
      raise ArgumentError,
            "Cannot fetch more than #{ARTIST_BATCH_LIMIT} artists at once"
    end

    client.get("artists", params: { ids: spotify_ids.join(",") })
  end

  private

  attr_reader :client
end
