# frozen_string_literal: true

module Filters
  module Sql
    module_function

    def contains(value)
      "%#{ActiveRecord::Base.sanitize_sql_like(value.to_s)}%"
    end

    def numeric?(value)
      value.to_s.match?(/\A\d+\z/)
    end
  end
end
