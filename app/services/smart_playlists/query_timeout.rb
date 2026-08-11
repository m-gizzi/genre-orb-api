# frozen_string_literal: true

module SmartPlaylists
  module QueryTimeout
    TIMEOUT_MS = 5_000
    PUSH_TIMEOUT_MS = 30_000

    def self.guard(timeout_ms = TIMEOUT_MS)
      ActiveRecord::Base.transaction do
        ActiveRecord::Base.connection.execute(statement(timeout_ms))
        yield
      end
    end

    def self.statement(timeout_ms)
      ActiveRecord::Base.sanitize_sql_array(["SET LOCAL statement_timeout = ?", timeout_ms])
    end
    private_class_method :statement
  end
end
