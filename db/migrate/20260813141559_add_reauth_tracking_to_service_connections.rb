# frozen_string_literal: true

class AddReauthTrackingToServiceConnections < ActiveRecord::Migration[8.1]
  def change
    add_column :service_connections, :needs_reauth, :boolean, default: false, null: false
    add_column :service_connections, :last_auth_error_at, :datetime
    add_column :service_connections, :last_auth_error, :string
  end
end
