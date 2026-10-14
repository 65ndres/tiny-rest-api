class AddSubscriptionTypeToSubscriptions < ActiveRecord::Migration[7.2]
  def change
    add_column :subscriptions, :subscription_type, :integer, default: 0, null: false
  end
end
