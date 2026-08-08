require "test_helper"

class Api::V1::ConversationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user1 = User.create!(
      email: "user1@example.com",
      password: "password123",
      password_confirmation: "password123",
      username: "user1",
      first_name: "John",
      last_name: "Doe"
    )
    @user2 = User.create!(
      email: "user2@example.com",
      password: "password123",
      password_confirmation: "password123",
      username: "user2",
      first_name: "Jane",
      last_name: "Smith"
    )
    @user3 = User.create!(
      email: "user3@example.com",
      password: "password123",
      password_confirmation: "password123",
      username: "user3"
    )

    @token1 = Warden::JWTAuth::UserEncoder.new.call(@user1, :user, nil).first
    @token2 = Warden::JWTAuth::UserEncoder.new.call(@user2, :user, nil).first
  end

  def auth_headers(token)
    { "Authorization" => "Bearer #{token}" }
  end

  test "should get index with no conversations" do
    get "/api/v1/user/conversations", headers: auth_headers(@token1)

    assert_response :success
    json_response = JSON.parse(response.body)
    assert_equal [], json_response["conversations"]
  end

  test "should get index with conversations" do
    conversation = Conversation.create!(conversation_type: 0, name: "Test Conversation")
    conversation.user_conversations.create!(user: @user1)
    conversation.user_conversations.create!(user: @user2)

    message = Message.create!(
      conversation: conversation,
      sender: @user2,
      body: "Hello there",
      read: false
    )

    get "/api/v1/user/conversations", headers: auth_headers(@token1)

    assert_response :success
    json_response = JSON.parse(response.body)
    assert_equal 1, json_response["conversations"].length
    assert_equal conversation.id, json_response["conversations"][0]["id"]
    assert_equal "Test Conversation", json_response["conversations"][0]["conversation_name"]
    assert_equal "Hello there", json_response["conversations"][0]["last_message"]["body"]
    assert_equal 1, conversation.messages.where.not(sender: @user1).where(read: false).count
  end

  test "should only return conversations of type 0" do
    conversation1 = Conversation.create!(conversation_type: 0, name: "Regular Conversation")
    conversation1.user_conversations.create!(user: @user1)

    conversation2 = Conversation.create!(conversation_type: 1, name: "Admin Conversation")
    conversation2.user_conversations.create!(user: @user1)

    get "/api/v1/user/conversations", headers: auth_headers(@token1)

    assert_response :success
    json_response = JSON.parse(response.body)
    assert_equal 1, json_response["conversations"].length
    assert_equal conversation1.id, json_response["conversations"][0]["id"]
  end

  test "should get admin conversation for current user only" do
    support = users(:support)
    own_thread = Conversation.find_or_create_support_for!(@user1)
    other_user_thread = Conversation.find_or_create_support_for!(@user2)

    Message.create!(
      conversation: own_thread,
      sender: @user1,
      body: "Admin message",
      read: true
    )

    get "/api/v1/conversations/admin_conversation", headers: auth_headers(@token1)

    assert_response :success
    json_response = JSON.parse(response.body)
    assert_equal own_thread.id, json_response["id"]
    assert_not_equal other_user_thread.id, json_response["id"]
    assert_equal @user1.id, json_response["current_user_id"]
    assert json_response["messages"].any? { |message| message["body"] == "Admin message" }
    assert_includes Conversation.find(json_response["id"]).users, support
  end

  test "admin_conversation creates a support thread when missing" do
    support = users(:support)
    @user1.conversations.support.find_each(&:destroy)

    assert_difference -> { Conversation.support.count }, 1 do
      get "/api/v1/conversations/admin_conversation", headers: auth_headers(@token1)
    end

    assert_response :success
    json_response = JSON.parse(response.body)
    conversation = Conversation.find(json_response["id"])
    assert conversation.support?
    assert_includes conversation.users, @user1
    assert_includes conversation.users, support
  end

  test "should get existing conversation by conversation_id" do
    conversation = Conversation.create!(conversation_type: 0, name: "Test")
    conversation.user_conversations.create!(user: @user1)
    conversation.user_conversations.create!(user: @user2)

    message1 = Message.create!(
      conversation: conversation,
      sender: @user1,
      body: "Message 1",
      read: false
    )
    message2 = Message.create!(
      conversation: conversation,
      sender: @user2,
      body: "Message 2",
      read: false
    )

    get "/api/v1/conversation/new", 
        params: { conversation_id: conversation.id },
        headers: auth_headers(@token1)

    assert_response :success
    json_response = JSON.parse(response.body)
    assert_equal conversation.id, json_response["id"]
    assert_equal 2, json_response["messages"].length
    assert_equal "Message 1", json_response["messages"][0]["body"]
    assert_equal "Message 2", json_response["messages"][1]["body"]
  end

  test "should mark messages as read when viewing conversation" do
    conversation = Conversation.create!(conversation_type: 0, name: "Test")
    conversation.user_conversations.create!(user: @user1)
    conversation.user_conversations.create!(user: @user2)

    message = Message.create!(
      conversation: conversation,
      sender: @user2,
      body: "Unread message",
      read: false
    )

    assert_equal false, message.read
    assert_equal false, conversation.read

    get "/api/v1/conversation/new",
        params: { conversation_id: conversation.id },
        headers: auth_headers(@token1)

    assert_response :success
    message.reload
    conversation.reload
    assert_equal true, message.read
    assert_equal true, conversation.read
  end

  test "should create new conversation when conversation_id not found" do
    get "/api/v1/conversation/new",
        params: { other_user_id: @user2.id },
        headers: auth_headers(@token1)

    assert_response :success
    json_response = JSON.parse(response.body)
    assert json_response["id"].present?
    assert_equal @user1.id, json_response["current_user_id"]
    assert_equal @user2.id, json_response["other_user_id"]
    assert_equal "Jane Smith", json_response["conversation_name"]
    assert_equal [], json_response["messages"]
  end

  test "should use username for conversation name when first_name and last_name not present" do
    get "/api/v1/conversation/new",
        params: { other_user_id: @user3.id },
        headers: auth_headers(@token1)

    assert_response :success
    json_response = JSON.parse(response.body)
    assert_equal "user3", json_response["conversation_name"]
  end

  test "should find existing conversation by other_user_id" do
    conversation = Conversation.create!(conversation_type: 0, name: "Existing")
    conversation.user_conversations.create!(user: @user1)
    conversation.user_conversations.create!(user: @user2)

    get "/api/v1/conversation/new",
        params: { other_user_id: @user2.id },
        headers: auth_headers(@token1)

    assert_response :success
    json_response = JSON.parse(response.body)
    assert_equal conversation.id, json_response["id"]
  end

  test "should create conversation with receiver username" do
    post "/api/v1/conversations",
         params: { receiver_username: @user2.username },
         headers: auth_headers(@token1)

    assert_response :created
    json_response = JSON.parse(response.body)
    assert json_response["id"].present?
    assert_equal "Conversation created successfully", json_response["message"]

    conversation = Conversation.find(json_response["id"])
    assert conversation.users.include?(@user1)
    assert conversation.users.include?(@user2)
  end

  test "should return existing conversation if already exists" do
    conversation = Conversation.create!(conversation_type: 0)
    conversation.user_conversations.create!(user: @user1)
    conversation.user_conversations.create!(user: @user2)

    post "/api/v1/conversations",
         params: { receiver_username: @user2.username },
         headers: auth_headers(@token1)

    assert_response :created
    json_response = JSON.parse(response.body)
    assert_equal conversation.id, json_response["id"]
  end

  test "should not create conversation with non-existent user" do
    post "/api/v1/conversations",
         params: { receiver_username: "nonexistent" },
         headers: auth_headers(@token1)

    assert_response :not_found
    json_response = JSON.parse(response.body)
    assert_equal "User not found", json_response["error"]
  end

  test "should not create conversation with yourself" do
    post "/api/v1/conversations",
         params: { receiver_username: @user1.username },
         headers: auth_headers(@token1)

    assert_response :unprocessable_entity
    json_response = JSON.parse(response.body)
    assert_equal "Cannot create conversation with yourself", json_response["error"]
  end

  test "should require authentication for index" do
    get "/api/v1/user/conversations"

    assert_response :unauthorized
  end

  test "should require authentication for new" do
    get "/api/v1/conversation/new", params: { conversation_id: 1 }

    assert_response :unauthorized
  end

  test "should require authentication for create" do
    post "/api/v1/conversations", params: { receiver_username: @user2.username }

    assert_response :unauthorized
  end

  test "should return conversations ordered by updated_at desc" do
    conversation1 = Conversation.create!(conversation_type: 0, name: "First", updated_at: 1.hour.ago)
    conversation1.user_conversations.create!(user: @user1)

    conversation2 = Conversation.create!(conversation_type: 0, name: "Second", updated_at: Time.now)
    conversation2.user_conversations.create!(user: @user1)

    get "/api/v1/user/conversations", headers: auth_headers(@token1)

    assert_response :success
    json_response = JSON.parse(response.body)
    assert_equal 2, json_response["conversations"].length
    assert_equal conversation2.id, json_response["conversations"][0]["id"]
    assert_equal conversation1.id, json_response["conversations"][1]["id"]
  end

  test "should return unread count for conversations" do
    conversation = Conversation.create!(conversation_type: 0, name: "Test")
    conversation.user_conversations.create!(user: @user1)
    conversation.user_conversations.create!(user: @user2)

    Message.create!(conversation: conversation, sender: @user2, body: "Unread 1", read: false)
    Message.create!(conversation: conversation, sender: @user2, body: "Unread 2", read: false)
    Message.create!(conversation: conversation, sender: @user1, body: "Read", read: true)

    get "/api/v1/user/conversations", headers: auth_headers(@token1)

    assert_response :success
    json_response = JSON.parse(response.body)
    unread_count = conversation.messages.where.not(sender: @user1).where(read: false).count
    assert_equal 2, unread_count
  end
end

