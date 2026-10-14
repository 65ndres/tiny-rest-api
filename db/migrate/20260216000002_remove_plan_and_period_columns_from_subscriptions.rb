class RemovePlanAndPeriodColumnsFromSubscriptions < ActiveRecord::Migration[7.2]
  def change
    # Remove the index on plan_id first
    remove_index :subscriptions, name: "index_subscriptions_on_plan_id", if_exists: true

    # Remove the foreign key constraint if it exists
    remove_foreign_key :subscriptions, :plans, if_exists: true

    # Remove the columns
    remove_column :subscriptions, :plan_id, :bigint
    remove_column :subscriptions, :current_period_start, :datetime
    remove_column :subscriptions, :current_period_end, :datetime
  end
end
