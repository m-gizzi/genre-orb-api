# frozen_string_literal: true

module Enrichment
  # One tick per source, process-wide. This is what makes Pacer's in-process sleep a
  # real rate limit rather than a per-worker one, so it is load-bearing rather than
  # merely tidy. The TTL is the backstop for a worker killed mid-tick.
  class Lock
    KEY_PREFIX = "genre_orb:enrichment:lock"

    # A tick that outlives the TTL loses the key, and the next tick takes it. An
    # unconditional DEL on the way out would then free a lock this tick no longer
    # owns, letting a third run concurrently — which is precisely the thing the lock
    # exists to prevent. Releasing only our own token closes that window.
    RELEASE = <<~LUA
      if redis.call("GET", KEYS[1]) == ARGV[1] then
        return redis.call("DEL", KEYS[1])
      end
      return 0
    LUA

    class << self
      # :ran, or :busy without yielding when another tick still holds the lock.
      def acquire(name, ttl:)
        key = "#{KEY_PREFIX}:#{name}"
        token = SecureRandom.uuid
        return :busy unless claimed?(key, token, ttl)

        begin
          yield
        ensure
          release(key, token)
        end

        :ran
      end

      private

      # Redis answers a SET NX with "OK", or nothing at all when the key already exists.
      def claimed?(key, token, ttl)
        AppRedis.with { |redis| redis.call("SET", key, token, "NX", "EX", ttl.to_i) }.present?
      end

      def release(key, token)
        AppRedis.with { |redis| redis.call("EVAL", RELEASE, 1, key, token) }
      end
    end
  end
end
