class CreateServiceConnections < ActiveRecord::Migration[8.1]
  def change
    create_table :service_connections do |t|
      t.references :user, null: false, foreign_key: true
      t.integer :service_type, null: false
      t.string :service_user_id, null: false
      t.text :access_token, null: false
      t.text :refresh_token
      t.datetime :token_expires_at
      t.jsonb :profile_data, default: {}

      t.timestamps
    end

    add_index :service_connections, [:user_id, :service_type], unique: true
    add_index :service_connections, [:service_type, :service_user_id], unique: true
  end
end
