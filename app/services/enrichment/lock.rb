# frozen_string_literal: true

module Enrichment
  # One tick per source, process-wide. This is what makes Pacer's in-process sleep a
  # real rate limit rather than a per-worker one, so it is load-bearing rather than
  # merely tidy. The TTL is the backstop for a worker killed mid-tick.
  class Lock
    KEY_PREFIX = "genre_orb:enrichment:lock"

    class << self
      # :ran, or :busy without yielding when another tick still holds the lock.
      def acquire(name, ttl:)
        key = "#{KEY_PREFIX}:#{name}"
        return :busy unless claimed?(key, ttl)

        begin
          yield
        ensure
          release(key)
        end

        :ran
      end

      private

      # Redis answers a SET NX with "OK", or nothing at all when the key already exists.
      def claimed?(key, ttl)
        AppRedis.with { |redis| redis.call("SET", key, Time.current.iso8601, "NX", "EX", ttl.to_i) }.present?
      end

      def release(key)
        AppRedis.with { |redis| redis.call("DEL", key) }
      end
    end
  end
end
