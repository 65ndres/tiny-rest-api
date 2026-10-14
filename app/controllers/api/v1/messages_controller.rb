class Api::V1::MessagesController < ApplicationController
  def index
    conversation = find_conversation(params[:conversation_id])

    unless conversation
      return render json: { error: "Conversation not found" }, status: :not_found
    end

    messages = conversation.messages.includes(:sender).order(created_at: :asc)

    conversation.messages.where.not(sender: current_user).where(read: false).update_all(read: true)

    render json: {
      messages: messages.map do |message|
        {
          id: message.id,
          sender: {
            id: message.sender.id,
            username: message.sender.username,
            first_name: message.sender.first_name,
            last_name: message.sender.last_name
          },
          body: message.body,
          read: message.read,
          created_at: message.created_at
        }
      end
    }, status: :ok
  end

  def create
    conversation = find_conversation(params[:conversation_id])

    unless conversation
      return render json: { error: "Conversation not found" }, status: :not_found
    end

    unless params[:body].present?
      return render json: { error: "Message body is required" }, status: :unprocessable_entity
    end

    message = conversation.messages.build(
      sender: current_user,
      body: params[:body]
    )

    if message.save
      render json: {
        id: message.id,
        sender: {
          id: message.sender.id,
          username: message.sender.username,
          first_name: message.sender.first_name,
          last_name: message.sender.last_name
        },
        body: message.body,
        read: message.read,
        created_at: message.created_at,
        message: "Message sent successfully"
      }, status: :created
    else
      render json: { errors: message.errors.full_messages }, status: :unprocessable_entity
    end
  end

  private

  def find_conversation(id)
    conversation = Conversation.find_by(id: id)
    return nil unless conversation

    conversation
  end
end
