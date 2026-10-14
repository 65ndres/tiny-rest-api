class CreateAdminMessages < ActiveRecord::Migration[7.2]
  def change
    create_table :admin_messages do |t|
      t.references :conversation, null: false, foreign_key: true
      t.references :sender, null: false, foreign_key: { to_table: :users }
      t.text :body, null: false
      t.boolean :read, default: false, null: false

      t.timestamps
    end
  end
end
