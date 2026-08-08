module Admin
  class MessagesController < BaseController
    def create
      conversation = Conversation.support.find(params[:conversation_id])
      unless conversation.users.exists?(id: current_support_user.id)
        raise ActiveRecord::RecordNotFound
      end

      body = params[:body].to_s.strip
      if body.blank?
        redirect_to admin_conversation_path(conversation), alert: 'Message cannot be empty.'
        return
      end

      conversation.messages.create!(
        body: body,
        sender: current_support_user,
        read: false
      )
      conversation.update(read: true, updated_at: Time.current)

      redirect_to admin_conversation_path(conversation), notice: 'Reply sent.'
    end
  end
end
