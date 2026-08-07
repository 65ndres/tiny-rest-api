# frozen_string_literal: true

class EnforceOneActiveSubscriptionPerUser < ActiveRecord::Migration[7.2]
  def up
    # Keep newest active subscription per user; expire the rest.
    execute <<~SQL
      UPDATE subscriptions AS s
      SET status = 1,
          active = false,
          updated_at = NOW()
      FROM (
        SELECT id,
               ROW_NUMBER() OVER (
                 PARTITION BY user_id
                 ORDER BY created_at DESC, id DESC
               ) AS rn
        FROM subscriptions
        WHERE status = 0
      ) AS ranked
      WHERE s.id = ranked.id
        AND ranked.rn > 1
    SQL

    # Mirror boolean active to status.
    execute <<~SQL
      UPDATE subscriptions
      SET active = (status = 0)
    SQL

    remove_index :subscriptions,
                 name: "index_subscriptions_on_user_id_active_unique",
                 if_exists: true

    add_index :subscriptions,
              :user_id,
              unique: true,
              where: "status = 0",
              name: "index_subscriptions_on_user_id_status_active_unique"
  end

  def down
    remove_index :subscriptions,
                 name: "index_subscriptions_on_user_id_status_active_unique",
                 if_exists: true

    add_index :subscriptions,
              :user_id,
              unique: true,
              where: "subscription_type = 0",
              name: "index_subscriptions_on_user_id_active_unique"
  end
end
