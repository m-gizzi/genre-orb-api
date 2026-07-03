# frozen_string_literal: true

class SmartPlaylistSource < ApplicationRecord
  belongs_to :smart_playlist, inverse_of: :smart_playlist_sources
  belongs_to :playlist, inverse_of: :smart_playlist_sources

  validates :smart_playlist_id, uniqueness: { scope: :playlist_id }
end
