# frozen_string_literal: true

class AddDayWindowMinutesToUsers < ActiveRecord::Migration[7.2]
  def change
    add_column :users, :day_start_minutes, :integer, null: false, default: 570
    add_column :users, :day_end_minutes, :integer, null: false, default: 1320
  end
end
