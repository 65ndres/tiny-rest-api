# frozen_string_literal: true

class AddPausedToTimerRuns < ActiveRecord::Migration[7.1]
  def change
    add_column :timer_runs, :paused, :boolean, null: false, default: false
  end
end
