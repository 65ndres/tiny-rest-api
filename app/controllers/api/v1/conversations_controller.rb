class Api::V1::ConversationsController < ApplicationController
  include ActionView::Helpers::DateHelper


  def index
    conversations = current_user.conversations
      .includes(:users, :messages)
      .where(conversation_type: 0)
      .order(updated_at: :desc)

    conversations_data = conversations.map do |conversation|
      last_message = conversation.messages.order(created_at: :desc).first
      unread_count = conversation.messages.where.not(sender: current_user).where(read: false).count
      
      {
        id: conversation.id,
        conversation_name: conversation.name,
        read: conversation.read,
        last_message: last_message ? {
          body: last_message.body,
          time: time_ago_in_words(last_message.created_at) + " ago",
          read: last_message.read
        } : nil,
      }
    end
    render json: { conversations: conversations_data }, status: :ok
  end

  def admin_conversation
    unless User.support_account
      return render json: { error: 'Support is unavailable' }, status: :service_unavailable
    end

    conversation = Conversation.find_or_create_support_for!(current_user)

    render json: {
      id: conversation.id,
      current_user_id: current_user.id,
      conversation_name: conversation.name,
      messages: conversation.messages.includes(:sender).order(created_at: :asc).map do |message|
        {
          id: message.id,
          sender_id: message.sender_id,
          body: message.body,
          read: message.read,
          created_at: message.created_at
        }
      end
    }, status: :ok
  rescue ArgumentError, ActiveRecord::RecordNotFound => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def new

    conversation = find_conversation

    if conversation
      messages = conversation.messages.includes(:sender).order(created_at: :asc)
      
      conversation.messages.where.not(sender: current_user).where(read: false).update_all(read: true)
      conversation.update(read: true)
      other_user = conversation.users.where.not(id: current_user.id).first
      render json: {
        id: conversation.id,
        current_user_id: current_user.id,
        other_user_id: other_user.id,
        conversation_name: conversation.name,
        messages: messages.map do |message|
          {
            id: message.id,
            sender_id: message.sender_id,
            body: message.body,
            read: message.read,
            created_at: message.created_at
          }
        end
      }, status: :ok
    elsif conversation.nil?
      other_user = User.find(params[:other_user_id])

      conversation = Conversation.create(name: define_conversation_name(other_user))
      conversation.user_conversations.create(user: current_user)
      conversation.user_conversations.create(user: other_user)
      conversation.update(read: true)
      render json: {
        id: conversation.id,
        current_user_id: current_user.id, 
        conversation_name: conversation.name,
        other_user_id: other_user.id,
        messages: []
      }, status: :ok
    else
      render json: { error: 'Conversation not found' }, status: :not_found
    end

  end

  def define_conversation_name(other_user)
    if other_user.first_name.present? && other_user.last_name.present?
      "#{other_user.first_name} #{other_user.last_name}"
    else
      other_user.username
    end
  end

  def create
    receiver = User.find_by(username: params[:receiver_username])
    
    unless receiver
      return render json: { error: 'User not found' }, status: :not_found
    end

    if receiver == current_user
      return render json: { error: 'Cannot create conversation with yourself' }, status: :unprocessable_entity
    end

    conversation = Conversation.between(current_user, receiver)
    
    unless conversation
      conversation = Conversation.create
      
      unless conversation.persisted?
        return render json: { errors: conversation.errors.full_messages }, status: :unprocessable_entity
      end
      
      conversation.user_conversations.create(user: current_user)
      conversation.user_conversations.create(user: receiver)
    end

    render json: {
      id: conversation.id,
      message: 'Conversation created successfully'
    }, status: :created
  end

  private

  def find_conversation
    conversation = nil
    if params[:conversation_id]
      conversation = Conversation.find_by(id: params[:conversation_id])
    elsif params[:other_user_id]
      conversation = Conversation.between(current_user, User.find(params[:other_user_id]))
    end
    conversation
  end
end

