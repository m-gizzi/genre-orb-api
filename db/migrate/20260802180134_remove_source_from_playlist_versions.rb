# frozen_string_literal: true

class RemoveSourceFromPlaylistVersions < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    remove_index :playlist_versions, column: %i[playlist_id source], algorithm: :concurrently
    safety_assured { remove_column :playlist_versions, :source }
  end

  def down
    add_column :playlist_versions, :source, :integer, default: 0, null: false
    add_index :playlist_versions, %i[playlist_id source], algorithm: :concurrently
  end
end
