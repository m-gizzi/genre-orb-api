# frozen_string_literal: true

class AddDescriptionToPlaylists < ActiveRecord::Migration[8.1]
  def change
    add_column :playlists, :description, :string
  end
end
