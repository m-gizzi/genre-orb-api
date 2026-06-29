# frozen_string_literal: true

class ServiceConnection < ApplicationRecord
  belongs_to :user

  encrypts :access_token
  encrypts :refresh_token

  enum :service_type, { spotify: 0 }, validate: true

  validates :service_user_id, presence: true
  validates :access_token, presence: true
  validates :user_id, uniqueness: { scope: :service_type, message: "already has a %{value} connection" }

  def token_expired?
    return true if token_expires_at.nil?

    token_expires_at <= Time.current
  end

  def token_expiring_soon?(buffer: 5.minutes)
    return true if token_expires_at.nil?

    token_expires_at <= buffer.from_now
  end
end
