class AddTimeZoneToUsers < ActiveRecord::Migration[7.2]
  def change
    add_column :users, :time_zone, :string, null: false, default: "UTC"
  end
end
