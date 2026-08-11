# frozen_string_literal: true

module FanInCounter
  extend ActiveSupport::Concern

  def advance_counter!(completed_column, total_column, **extra_attributes)
    with_lock do
      assign_attributes(extra_attributes.compact)
      self[completed_column] += 1
      save!

      self[completed_column] >= self[total_column]
    end
  end
end
