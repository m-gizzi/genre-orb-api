# frozen_string_literal: true

class RemoveIsPublicFromPlaylists < ActiveRecord::Migration[8.1]
  def change
    safety_assured do
      remove_column :playlists, :is_public, :boolean, default: false, null: false
    end
  end
end
