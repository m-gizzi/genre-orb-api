# frozen_string_literal: true

class AddGenreSourcePreferencesToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :genre_source_preferences, :jsonb, null: false, default: {}
  end
end
