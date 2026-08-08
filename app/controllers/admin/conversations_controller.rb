module Admin
  class ConversationsController < BaseController
    def index
      @conversations = Conversation
        .support
        .includes(:users, :messages)
        .left_joins(:messages)
        .select(
          'conversations.*',
          'MAX(messages.created_at) AS last_message_at'
        )
        .group('conversations.id')
        .order(Arel.sql('MAX(messages.created_at) DESC NULLS LAST, conversations.updated_at DESC'))
    end

    def show
      @conversation = find_support_conversation!
      @customer = @conversation.other_user(current_support_user)
      @messages = @conversation.messages.includes(:sender).order(created_at: :asc)

      @conversation.messages
        .where.not(sender: current_support_user)
        .where(read: false)
        .update_all(read: true)
      @conversation.update(read: true)
    end

    private

    def find_support_conversation!
      conversation = Conversation.support.find(params[:id])
      unless conversation.users.exists?(id: current_support_user.id)
        raise ActiveRecord::RecordNotFound
      end
      conversation
    end
  end
end
