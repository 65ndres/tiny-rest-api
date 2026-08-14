# frozen_string_literal: true

class AddDailyNapCountAltToUsers < ActiveRecord::Migration[7.2]
  def change
    add_column :users, :daily_nap_count_alt, :integer
  end
end
