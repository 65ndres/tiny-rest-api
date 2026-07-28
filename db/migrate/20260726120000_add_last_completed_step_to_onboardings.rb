class AddLastCompletedStepToOnboardings < ActiveRecord::Migration[7.2]
  def change
    add_column :onboardings, :last_completed_step, :string
  end
end
