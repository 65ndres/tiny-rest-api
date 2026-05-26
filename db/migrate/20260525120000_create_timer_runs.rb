class CreateTimerRuns < ActiveRecord::Migration[7.2]
  def change
    create_table :timer_runs do |t|
      t.references :user, null: true, foreign_key: true
      t.datetime :start_time, null: false
      t.datetime :end_time
      t.integer :duration
      t.boolean :submitted, null: false, default: false

      t.timestamps
    end

    add_index :timer_runs, [:user_id, :submitted]
  end
end
