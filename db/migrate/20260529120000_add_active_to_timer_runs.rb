# frozen_string_literal: true

class AddActiveToTimerRuns < ActiveRecord::Migration[7.2]
  def change
    add_column :timer_runs, :active, :boolean, null: false, default: false
    add_index :timer_runs, :user_id,
              unique: true,
              where: 'active = true',
              name: 'index_timer_runs_one_active_per_user'
  end
end
