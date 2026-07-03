# frozen_string_literal: true

class CreateSmartPlaylists < ActiveRecord::Migration[8.1]
  def change
    create_table :smart_playlists do |t|
      t.references :user, null: false, foreign_key: true
      t.string :name, null: false
      t.references :target_playlist, null: true, foreign_key: { to_table: :playlists }
      t.jsonb :rules, null: false, default: {}
      t.boolean :is_enabled, default: true, null: false
      t.datetime :last_evaluated_at
      t.datetime :last_pushed_at
      t.integer :match_count, default: 0, null: false

      t.timestamps
    end

    add_index :smart_playlists, [:user_id, :name], unique: true
    add_index :smart_playlists, :is_enabled
    add_index :smart_playlists, :last_evaluated_at
  end
end
