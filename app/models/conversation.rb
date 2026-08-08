class Conversation < ApplicationRecord
  SUPPORT_TYPE = 1

  has_many :user_conversations, dependent: :destroy
  has_many :users, through: :user_conversations
  has_many :messages, dependent: :destroy

  scope :support, -> { where(conversation_type: SUPPORT_TYPE) }

  # Find or create a conversation between two users
  def self.between(user1, user2)
    # Find conversations that have both users (exactly these two)
    joins(:users)
      .where(users: { id: [user1.id, user2.id] })
      .group('conversations.id')
      .having('COUNT(DISTINCT users.id) = ?', 2)
      .first
  end

  # Per-user support thread with the Support account (conversation_type: 1).
  def self.find_or_create_support_for!(user)
    support = User.support_account
    raise ActiveRecord::RecordNotFound, 'Support user not found' if support.nil?
    raise ArgumentError, 'Cannot create a support conversation for the Support user' if user.support_account?

    existing = support
      .conversations
      .support
      .joins(:users)
      .where(users: { id: user.id })
      .distinct
      .first

    return existing if existing

    create!(name: 'Support', conversation_type: SUPPORT_TYPE).tap do |conversation|
      conversation.users << user
      conversation.users << support
    end
  end

  # Get the other user(s) in the conversation (excluding the given user)
  def other_users(user)
    users.where.not(id: user.id)
  end

  # Get the other user in a two-person conversation
  def other_user(user)
    other_users = users.where.not(id: user.id)
    other_users.first if other_users.count == 1
  end

  def support?
    conversation_type == SUPPORT_TYPE
  end

  def last_message
    messages.order(created_at: :desc).first
  end
end


