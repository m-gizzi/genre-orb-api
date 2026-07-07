# frozen_string_literal: true

class RemoveTrackCountFromPlaylists < ActiveRecord::Migration[8.1]
  def change
    safety_assured { remove_column :playlists, :track_count, :integer }
  end
end
