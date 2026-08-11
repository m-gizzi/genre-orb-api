# frozen_string_literal: true

class SessionSerializer
  include Alba::Resource

  attributes :id, :status, :progress, :error_message

  attribute :started_at do |session|
    session.started_at&.iso8601
  end

  attribute :completed_at do |session|
    session.completed_at&.iso8601
  end
end
