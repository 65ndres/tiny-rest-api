class AddBabyNameAndDailyNapCountToUsers < ActiveRecord::Migration[7.2]
  def change
    add_column :users, :baby_name, :string
    add_column :users, :daily_nap_count, :integer, null: false, default: 3
  end
end
