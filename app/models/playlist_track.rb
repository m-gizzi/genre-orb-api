# frozen_string_literal: true

class PlaylistTrack < ApplicationRecord
  belongs_to :playlist, inverse_of: :playlist_tracks, counter_cache: :track_count
  belongs_to :track, inverse_of: :playlist_tracks

  validates :position, presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :playlist_id, uniqueness: { scope: :track_id }
end
