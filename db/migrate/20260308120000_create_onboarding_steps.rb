class CreateOnboardingSteps < ActiveRecord::Migration[7.2]
  def change
    create_table :onboarding_steps do |t|
      t.references :onboarding, null: false, foreign_key: true
      t.integer :position, null: false
      t.string :step_name, null: false
      t.datetime :completed_at

      t.timestamps
    end

    add_index :onboarding_steps, [ :onboarding_id, :position ], unique: true
  end
end
