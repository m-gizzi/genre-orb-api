class AddStatusToPlaylistVersions < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_column :playlist_versions, :status, :integer, default: 0, null: false
    add_index :playlist_versions, :status, algorithm: :concurrently
  end
end
