# frozen_string_literal: true

# Spotify throttles per application, not per user, so a 429 raised on a request
# with no user behind it (the app token) pauses everything. A user's own pause is
# the longer of the two.
class SyncRateLimitState
  GLOBAL_KEY = "genre_orb:sync:rate_limit:global"

  class << self
    def pause!(user_id, seconds)
      with_redis do |redis|
        redis.call("SETEX", key_for(user_id), seconds.to_i, Time.current.iso8601)
      end
    end

    def user_paused?(user_id)
      wait_time_for_user(user_id).positive?
    end

    def user_resume_at(user_id)
      wait = wait_time_for_user(user_id)
      return nil if wait.zero?

      Time.current + wait
    end

    def wait_time_for_user(user_id)
      [ttl(key_for(user_id)), ttl(GLOBAL_KEY), 0].max
    end

    private

    def ttl(key)
      with_redis { |redis| redis.call("TTL", key) }
    end

    def with_redis(&)
      AppRedis.with(&)
    end

    def key_for(user_id)
      user_id ? "genre_orb:sync:rate_limit:user:#{user_id}" : GLOBAL_KEY
    end
  end
end
