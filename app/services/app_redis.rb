# frozen_string_literal: true

class AppRedis
  class << self
    def with(&)
      pool.with(&)
    end

    private

    def pool
      @pool ||= RedisClient.config(url: url).new_pool(size: 5, timeout: 5)
    end

    def url
      ENV.fetch("REDIS_URL", "redis://localhost:6379/1")
    end
  end
end
