# frozen_string_literal: true

class SpotifyAdapter
  ARTIST_BATCH_LIMIT = 50
  TRACK_BATCH_LIMIT = 100
  PLAYLIST_TRACK_LIMIT = 10_000

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

  def playlist_snapshot_id(playlist_id)
    client.get("playlists/#{playlist_id}", params: { fields: "snapshot_id" })&.fetch("snapshot_id", nil)
  end

  def add_tracks_to_playlist(playlist_id, spotify_ids)
    guard_track_batch!(spotify_ids, "add")

    client.post("playlists/#{playlist_id}/tracks", body: { uris: track_uris(spotify_ids) })
  end

  def remove_tracks_from_playlist(playlist_id, spotify_ids)
    guard_track_batch!(spotify_ids, "remove")

    body = { tracks: track_uris(spotify_ids).map { |uri| { uri: uri } } }
    client.delete("playlists/#{playlist_id}/tracks", body: body)
  end

  def clear_playlist(playlist_id)
    client.put("playlists/#{playlist_id}/tracks", body: { uris: [] })
  end

  private

  attr_reader :client

  def guard_track_batch!(spotify_ids, verb)
    return if spotify_ids.size <= TRACK_BATCH_LIMIT

    raise ArgumentError, "Cannot #{verb} more than #{TRACK_BATCH_LIMIT} tracks at once"
  end

  def track_uris(spotify_ids)
    spotify_ids.map { |id| "spotify:track:#{id}" }
  end
end
