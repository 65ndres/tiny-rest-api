class AdminConversation < Conversation
  has_many :user_conversations, dependent: :destroy
  has_many :users, through: :user_conversations
  has_many :messages, dependent: :destroy


  scope :unread, -> { where(read: false) }
  scope :read, -> { where(read: true) }
end
