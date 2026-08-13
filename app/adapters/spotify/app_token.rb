# frozen_string_literal: true

module Spotify
  class AppToken
    CACHE_KEY = "genre_orb:spotify:app_token"
    EXPIRY_BUFFER = 60

    def user_id
      nil
    end

    def expiring_soon?
      false
    end

    def flag_needs_reauth!(_message)
      nil
    end

    def access_token
      memoized || store(cached || mint)
    end

    def refresh!
      @memo = nil
      store(mint)
    end

    private

    def memoized
      @memo if @memo && @memo_expires_at&.future?
    end

    def store((token, ttl))
      @memo = token
      @memo_expires_at = ttl.seconds.from_now
      token
    end

    def cached
      ttl = AppRedis.with { |redis| redis.call("TTL", CACHE_KEY) }
      return nil unless ttl.positive?

      token = AppRedis.with { |redis| redis.call("GET", CACHE_KEY) }
      token && [token, ttl]
    end

    def mint
      response = TokenSource.request(grant_type: "client_credentials")
      raise TokenRefreshError, "Failed to fetch app token: #{response.body}" unless response.success?

      cache(JSON.parse(response.body))
    end

    def cache(data)
      ttl = [data["expires_in"].to_i - EXPIRY_BUFFER, EXPIRY_BUFFER].max
      token = data["access_token"]
      AppRedis.with { |redis| redis.call("SETEX", CACHE_KEY, ttl, token) }
      [token, ttl]
    end
  end
end
