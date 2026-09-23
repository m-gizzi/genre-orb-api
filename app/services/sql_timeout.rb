# frozen_string_literal: true

module SqlTimeout
  class << self
    # For a caller that already has a transaction open for its own reasons — atomicity,
    # not timing — and should keep owning it.
    def apply(statement: nil, lock: nil)
      { "statement_timeout" => statement, "lock_timeout" => lock }.compact.each do |setting, value|
        execute(setting, value)
      end
    end

    # For a caller whose only reason to open a transaction is to scope the timeouts.
    # Returns the block's value. Called inside an existing transaction Rails joins it
    # rather than nesting, so the cap extends to that one.
    def guard(statement: nil, lock: nil)
      ActiveRecord::Base.transaction do
        apply(statement: statement, lock: lock)
        yield
      end
    end

    private

    def execute(setting, value)
      ActiveRecord::Base.connection.execute(
        ActiveRecord::Base.sanitize_sql_array(["SET LOCAL #{setting} = ?", value]),
      )
    end
  end
end
