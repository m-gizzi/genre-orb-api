# frozen_string_literal: true

class RemoveTrackIdsFromPlaylistVersions < ActiveRecord::Migration[8.1]
  def change
    safety_assured do
      remove_column :playlist_versions, :track_ids, :bigint, array: true, default: []
    end
  end
end
