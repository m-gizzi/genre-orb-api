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

  def fail!(error_message:)
    return if failed?

    update!(status: :failed, error_message: error_message, completed_at: Time.current)
  end
end
