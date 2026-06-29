class AddRegistrationSourceToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :registration_source, :integer, default: 0, null: false
  end
end
