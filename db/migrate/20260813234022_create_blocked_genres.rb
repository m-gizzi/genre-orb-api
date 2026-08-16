# frozen_string_literal: true

class CreateBlockedGenres < ActiveRecord::Migration[8.1]
  def change
    create_table :blocked_genres do |t|
      t.references :user, null: false, foreign_key: true
      t.references :genre, null: false, foreign_key: true

      t.timestamps
    end

    add_index :blocked_genres, %i[user_id genre_id], unique: true
  end
end
