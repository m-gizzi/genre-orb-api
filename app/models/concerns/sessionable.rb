# frozen_string_literal: true

module Sessionable
  extend ActiveSupport::Concern
  include FanInCounter

  included do
    scope :active, -> { where(status: %i[pending running]) }
    scope :recent, -> { order(created_at: :desc) }
  end

  def active?
    pending? || running?
  end
end
