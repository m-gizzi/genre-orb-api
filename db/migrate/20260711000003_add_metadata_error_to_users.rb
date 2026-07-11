# frozen_string_literal: true

class AddMetadataErrorToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :playlists_metadata_error, :string
  end
end
