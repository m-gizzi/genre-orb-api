# frozen_string_literal: true

class SpotifyAdapter
  class Catalog
    def self.app
      new(Spotify::Client.new(Spotify::AppToken.new))
    end

    def initialize(client)
      @client = client
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
end
