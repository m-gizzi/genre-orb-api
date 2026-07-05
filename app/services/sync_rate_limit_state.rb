# frozen_string_literal: true

class SyncRateLimitState
  class << self
    def pause_user!(user_id, seconds)
      with_redis do |redis|
        redis.call("SETEX", user_key(user_id), seconds.to_i, Time.current.iso8601)
      end
    end

    def user_paused?(user_id)
      with_redis { |redis| redis.call("EXISTS", user_key(user_id)) > 0 }
    end

    def user_resume_at(user_id)
      ttl = with_redis { |redis| redis.call("TTL", user_key(user_id)) }
      return nil if ttl <= 0

      Time.current + ttl
    end

    def wait_time_for_user(user_id)
      ttl = with_redis { |redis| redis.call("TTL", user_key(user_id)) }
      [ttl, 0].max
    end

    private

    def with_redis(&block)
      redis_pool.with(&block)
    end

    def redis_pool
      @redis_pool ||= RedisClient.config(url: redis_url).new_pool(size: 5, timeout: 5)
    end

    def redis_url
      ENV.fetch("REDIS_URL", "redis://localhost:6379/1")
    end

    def user_key(user_id)
      "genre_orb:sync:rate_limit:user:#{user_id}"
    end
  end
end
