# frozen_string_literal: true

module AppRedisStubbing
  # Not and_yield: it discards the block's return value, and every caller of
  # AppRedis.with reads it.
  def stub_app_redis(client)
    allow(AppRedis).to receive(:with) { |&block| block.call(client) } # rubocop:disable RSpec/Yield
  end
end

# Nothing in the suite should reach a live Redis. The default client reports
# every key as absent; specs that care about what was written stub their own.
RSpec.configure do |config|
  config.include AppRedisStubbing

  config.before do
    null_redis = instance_double(RedisClient)
    # -2 is Redis's "no such key" TTL, which is what every read should see against an
    # empty store. A SET has to look like it succeeded, though, or nothing that takes
    # a lock (Enrichment::Lock) can run under the default stub.
    allow(null_redis).to receive(:call) { |command, *| command == "SET" ? "OK" : -2 }
    stub_app_redis(null_redis)
  end
end
