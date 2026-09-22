# frozen_string_literal: true

class PlaylistVersionPruneJob < ApplicationJob
  queue_as :default

  sidekiq_options retry: false

  def perform
    Rails.logger.info("PlaylistVersionPruneJob: #{PlaylistVersions::Pruner.new.call}")
  rescue StandardError => e
    Rails.logger.error("PlaylistVersionPruneJob failed (#{e.class}): #{e.message}")
  end
end
