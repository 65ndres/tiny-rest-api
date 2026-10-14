class Message < ApplicationRecord
  belongs_to :conversation
  belongs_to :sender, class_name: "User"

  after_create :mark_conversation_as_unread

  scope :unread, -> { where(read: false) }
  scope :read, -> { where(read: true) }

  private

  def mark_conversation_as_unread
    conversation.update(read: false)
  end
end
