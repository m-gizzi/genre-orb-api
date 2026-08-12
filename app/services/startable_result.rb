# frozen_string_literal: true

module StartableResult
  def started?
    outcome == :started
  end
end
