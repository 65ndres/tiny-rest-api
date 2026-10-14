class CreateMessages < ActiveRecord::Migration[7.2]
  def change
    create_table :messages do |t|
      t.references :conversation, null: false, foreign_key: true
      t.references :sender, null: false, foreign_key: { to_table: :users }
      t.references :receiver, null: false, foreign_key: { to_table: :users }
      t.text :body, null: false
      t.boolean :read, default: false, null: false

      t.timestamps
    end

    # add_index :messages, :conversation_id
    # add_index :messages, :sender_id
    # add_index :messages, :receiver_id
  end
end
