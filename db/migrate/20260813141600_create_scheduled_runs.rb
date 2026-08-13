# frozen_string_literal: true

class CreateScheduledRuns < ActiveRecord::Migration[8.1]
  def up
    create_table :scheduled_runs do |t|
      t.date :run_date, null: false
      t.integer :status, default: 0, null: false
      t.integer :stage, default: 0, null: false
      t.datetime :stage_started_at
      t.integer :stage_total, default: 0, null: false
      t.integer :stage_completed, default: 0, null: false
      t.integer :push_wave, default: 0, null: false
      t.jsonb :push_plan, default: [], null: false
      t.jsonb :stage_errors, default: {}, null: false
      t.datetime :started_at
      t.datetime :completed_at
      t.string :error_message

      t.timestamps
    end

    add_index :scheduled_runs, :run_date, unique: true
    add_index :scheduled_runs, :status

    safety_assured do
      execute <<~SQL.squish
        CREATE UNIQUE INDEX idx_single_active_scheduled_run
          ON scheduled_runs ((status IS NOT NULL))
          WHERE status IN (0, 1)
      SQL
    end
  end

  def down
    drop_table :scheduled_runs
  end
end
