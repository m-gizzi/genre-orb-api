class CreateArtistMetadataSessions < ActiveRecord::Migration[8.1]
  def change
    create_table :artist_metadata_sessions do |t|
      t.references :user, null: false, foreign_key: true
      t.integer :status, null: false, default: 0
      t.integer :total_batches, null: false, default: 0
      t.integer :completed_batches, null: false, default: 0
      t.datetime :started_at
      t.datetime :completed_at
      t.string :error_message

      t.timestamps
    end

    add_index :artist_metadata_sessions, :status
    add_index :artist_metadata_sessions, %i[user_id status]
  end
end
