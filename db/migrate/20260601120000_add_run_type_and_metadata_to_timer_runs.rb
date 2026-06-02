# frozen_string_literal: true

class AddRunTypeAndMetadataToTimerRuns < ActiveRecord::Migration[7.2]
  def change
    add_column :timer_runs, :run_type, :string, null: false, default: "sleeping"
    add_column :timer_runs, :metadata, :jsonb, null: false, default: {}

    add_index :timer_runs, [:user_id, :run_type]
  end
end
