# frozen_string_literal: true

class AddPlaylistsMetadataFetchedAtToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :playlists_metadata_fetched_at, :datetime
  end
end
