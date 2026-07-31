# frozen_string_literal: true

module Spotify
  class PlayableTrackItems
    def initialize(items)
      @items = items
    end

    def call
      playable, rejected = @items.partition { |item| playable?(item["track"]) }
      log_rejected(rejected)
      playable
    end

    private

    def playable?(track)
      return false unless track && track["id"]
      return false if track["type"].present? && track["type"] != "track"

      track["name"].present? && !track["duration_ms"].to_i.zero?
    end

    def log_rejected(rejected)
      return if rejected.empty?

      counts = rejected.group_by { |item| rejection_reason(item["track"]) }
                       .transform_values(&:size)
                       .sort
                       .map { |reason, count| "#{reason}=#{count}" }
                       .join(" ")

      Rails.logger.info("Spotify sync skipped #{rejected.size} unplayable item(s): #{counts}")
    end

    def rejection_reason(track)
      return :missing_id unless track && track["id"]
      return :not_a_track if track["type"].present? && track["type"] != "track"
      return :blank_title if track["name"].blank?

      :zero_duration
    end
  end
end
