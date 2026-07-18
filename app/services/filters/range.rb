# frozen_string_literal: true

module Filters
  module Range
    module_function

    def bounded(minimum, maximum)
      minimum = minimum.presence
      maximum = maximum.presence
      return nil unless minimum || maximum
      return (minimum..maximum) if minimum && maximum

      minimum ? (minimum..) : (..maximum)
    end
  end
end
