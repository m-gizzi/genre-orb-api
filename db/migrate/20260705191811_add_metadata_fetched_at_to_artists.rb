class AddMetadataFetchedAtToArtists < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_column :artists, :metadata_fetched_at, :datetime
    add_index :artists, :metadata_fetched_at, algorithm: :concurrently
  end
end
