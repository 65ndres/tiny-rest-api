class CreateUserConversations < ActiveRecord::Migration[7.2]
  def change
    create_table :user_conversations do |t|
      t.references :user, null: false, foreign_key: true
      t.references :conversation, null: false, foreign_key: true

      t.timestamps
    end

    add_index :user_conversations, [ :user_id, :conversation_id ], unique: true
  end
end
