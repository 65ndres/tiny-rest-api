class RemoveSenderReceiverFromConversations < ActiveRecord::Migration[7.2]
  def change
    remove_foreign_key :conversations, :users, column: :sender_id
    remove_foreign_key :conversations, :users, column: :receiver_id
    remove_index :conversations, [ :sender_id, :receiver_id ] if index_exists?(:conversations, [ :sender_id, :receiver_id ])
    remove_column :conversations, :sender_id, :bigint
    remove_column :conversations, :receiver_id, :bigint
  end
end
