# frozen_string_literal: true

class PlaylistVersionTrack < ApplicationRecord
  belongs_to :playlist_version, inverse_of: :playlist_version_tracks
  belongs_to :track, inverse_of: :playlist_version_tracks

  validates :position, presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 0 },
                       uniqueness: { scope: :playlist_version_id }
end
