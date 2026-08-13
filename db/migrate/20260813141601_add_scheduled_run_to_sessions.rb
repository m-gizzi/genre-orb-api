# frozen_string_literal: true

class AddScheduledRunToSessions < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  TABLES = %i[sync_sessions artist_metadata_sessions push_sessions].freeze

  def change
    TABLES.each do |table|
      add_reference table, :scheduled_run,
                    null: true,
                    index: { algorithm: :concurrently },
                    foreign_key: { validate: false }
    end
  end
end
