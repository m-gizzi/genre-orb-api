# frozen_string_literal: true

module SmartPlaylists
  module QueryTimeout
    TIMEOUT_MS = 5_000
    PUSH_TIMEOUT_MS = 30_000

    def self.guard(timeout_ms = TIMEOUT_MS, &)
      SqlTimeout.guard(statement: timeout_ms, &)
    end
  end
end
