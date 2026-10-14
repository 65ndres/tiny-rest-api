class RemoveStatusFromSubscriptions < ActiveRecord::Migration[7.2]
  def change
    # Remove the old index that depends on status column
    remove_index :subscriptions, name: "index_subscriptions_on_user_id_active_unique", if_exists: true

    # Remove the status column
    remove_column :subscriptions, :status, :integer

    # Re-add the unique constraint using subscription_type instead
    add_index :subscriptions, :user_id,
              unique: true,
              where: "subscription_type = 0",
              name: "index_subscriptions_on_user_id_active_unique"
  end
end
