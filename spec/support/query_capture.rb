# frozen_string_literal: true

module QueryCapture
  # The SQL issued while the block runs, for asserting a preload really is one query.
  def queries_during
    captured = []
    subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
      captured << payload[:sql]
    end
    yield
    captured
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber) if subscriber
  end
end

RSpec.configure do |config|
  config.include QueryCapture
end
