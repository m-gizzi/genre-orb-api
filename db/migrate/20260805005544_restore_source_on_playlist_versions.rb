# frozen_string_literal: true

class RestoreSourceOnPlaylistVersions < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_column :playlist_versions, :source, :integer, default: 0, null: false
    add_index :playlist_versions, %i[playlist_id source], algorithm: :concurrently
  end
end
