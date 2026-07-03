# frozen_string_literal: true

class AddSourceToTrackGenres < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_column :track_genres, :source, :integer, null: false, default: 0
    add_index :track_genres, :source, algorithm: :concurrently
  end
end
