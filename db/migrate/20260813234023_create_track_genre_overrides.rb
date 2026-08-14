# frozen_string_literal: true

class CreateTrackGenreOverrides < ActiveRecord::Migration[8.1]
  def change
    create_table :track_genre_overrides do |t|
      t.references :user, null: false, foreign_key: true
      t.references :track, null: false, foreign_key: true
      t.references :genre, null: false, foreign_key: true
      t.integer :action, null: false

      t.timestamps
    end

    add_index :track_genre_overrides, %i[user_id track_id genre_id], unique: true
    add_index :track_genre_overrides, %i[user_id action]
  end
end
