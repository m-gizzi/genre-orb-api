# frozen_string_literal: true

module SmartPlaylists
  # Spotify removes every occurrence of a uri, so a track held twice is repaired by
  # deleting it wholesale in the remove phase and re-adding it once in the add phase.
  # That is the reason the two phases cannot be interleaved.
  class PushDiff
    def initialize(desired:, current:)
      @desired = desired
      @current = current
    end

    def to_remove
      @to_remove ||= current_counts.filter_map do |spotify_id, count|
        spotify_id if count > 1 || desired_set.exclude?(spotify_id)
      end
    end

    def to_add
      @to_add ||= desired.reject { |spotify_id| current_counts[spotify_id] == 1 }
    end

    private

    attr_reader :desired, :current

    def desired_set
      @desired_set ||= desired.to_set
    end

    def current_counts
      @current_counts ||= current.tally
    end
  end
end
