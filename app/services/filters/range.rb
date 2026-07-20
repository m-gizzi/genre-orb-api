# frozen_string_literal: true

module Filters
  module Range
    module_function

    def bounded(minimum, maximum)
      minimum = coerce(minimum)
      maximum = coerce(maximum)
      return nil unless minimum || maximum
      return (minimum..maximum) if minimum && maximum

      minimum ? (minimum..) : (..maximum)
    end

    def coerce(value)
      return nil if value.blank?

      Integer(value, exception: false)
    end
  end
end
