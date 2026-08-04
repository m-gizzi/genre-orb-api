# frozen_string_literal: true

module SmartPlaylists
  module QueryTimeout
    TIMEOUT_MS = 5_000

    def self.guard
      ActiveRecord::Base.transaction do
        ActiveRecord::Base.connection.execute(statement)
        yield
      end
    end

    def self.statement
      ActiveRecord::Base.sanitize_sql_array(["SET LOCAL statement_timeout = ?", TIMEOUT_MS])
    end
    private_class_method :statement
  end
end
