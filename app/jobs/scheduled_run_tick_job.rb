# frozen_string_literal: true

class ScheduledRunTickJob < ApplicationJob
  queue_as :default

  sidekiq_options retry: false

  def perform
    ScheduledRuns::Supervisor.new.call
  rescue StandardError => e
    Rails.logger.error("ScheduledRunTickJob failed (#{e.class}): #{e.message}")
  end
end
