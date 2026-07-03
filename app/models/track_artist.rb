# frozen_string_literal: true

class TrackArtist < ApplicationRecord
  belongs_to :track, inverse_of: :track_artists
  belongs_to :artist, inverse_of: :track_artists

  validates :track_id, uniqueness: { scope: :artist_id }
end
