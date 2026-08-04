# frozen_string_literal: true

module Rules
  module Excerpt
    MAX_LENGTH = 40
    MAX_ENTRIES = 5

    class << self
      def of(value)
        value.inspect.truncate(MAX_LENGTH)
      end

      def list(values)
        values.first(MAX_ENTRIES).map { |value| of(value) }.join(", ")
      end
    end
  end
end
