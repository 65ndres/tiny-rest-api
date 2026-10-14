class AddStatusToSubscriptions < ActiveRecord::Migration[7.2]
  def change
    add_column :subscriptions, :status, :integer,
    default: 0, null: false
  end
end
