require "test_helper"

class Api::V1::MessagesControllerTest < ActionDispatch::IntegrationTest
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

    @token1 = Warden::JWTAuth::UserEncoder.new.call(@user1, :user, nil).first
    @token2 = Warden::JWTAuth::UserEncoder.new.call(@user2, :user, nil).first

    @conversation = Conversation.create!(conversation_type: 0, name: "Test Conversation")
    @conversation.user_conversations.create!(user: @user1)
    @conversation.user_conversations.create!(user: @user2)
  end

  def auth_headers(token)
    { "Authorization" => "Bearer #{token}" }
  end

  test "should get index with no messages" do
    get "/api/v1/conversations/#{@conversation.id}/messages", headers: auth_headers(@token1)

    assert_response :success
    json_response = JSON.parse(response.body)
    assert_equal [], json_response["messages"]
  end

  test "should get index with messages" do
    message1 = Message.create!(
      conversation: @conversation,
      sender: @user1,
      body: "Hello",
      read: false
    )
    message2 = Message.create!(
      conversation: @conversation,
      sender: @user2,
      body: "Hi there",
      read: false
    )

    get "/api/v1/conversations/#{@conversation.id}/messages", headers: auth_headers(@token1)

    assert_response :success
    json_response = JSON.parse(response.body)
    assert_equal 2, json_response["messages"].length
    assert_equal message1.id, json_response["messages"][0]["id"]
    assert_equal message2.id, json_response["messages"][1]["id"]
    assert_equal "Hello", json_response["messages"][0]["body"]
    assert_equal "Hi there", json_response["messages"][1]["body"]
  end

  test "should return messages ordered by created_at asc" do
    message1 = Message.create!(
      conversation: @conversation,
      sender: @user1,
      body: "First",
      read: false,
      created_at: 1.hour.ago
    )
    message2 = Message.create!(
      conversation: @conversation,
      sender: @user2,
      body: "Second",
      read: false,
      created_at: Time.now
    )

    get "/api/v1/conversations/#{@conversation.id}/messages", headers: auth_headers(@token1)

    assert_response :success
    json_response = JSON.parse(response.body)
    assert_equal 2, json_response["messages"].length
    assert_equal message1.id, json_response["messages"][0]["id"]
    assert_equal message2.id, json_response["messages"][1]["id"]
  end

  test "should include sender information in messages" do
    message = Message.create!(
      conversation: @conversation,
      sender: @user2,
      body: "Test message",
      read: false
    )

    get "/api/v1/conversations/#{@conversation.id}/messages", headers: auth_headers(@token1)

    assert_response :success
    json_response = JSON.parse(response.body)
    sender = json_response["messages"][0]["sender"]
    assert_equal @user2.id, sender["id"]
    assert_equal @user2.username, sender["username"]
    assert_equal @user2.first_name, sender["first_name"]
    assert_equal @user2.last_name, sender["last_name"]
  end

  test "should mark messages as read when viewing them" do
    message = Message.create!(
      conversation: @conversation,
      sender: @user2,
      body: "Unread message",
      read: false
    )

    assert_equal false, message.read

    get "/api/v1/conversations/#{@conversation.id}/messages", headers: auth_headers(@token1)

    assert_response :success
    message.reload
    assert_equal true, message.read
  end

  test "should only mark messages from other users as read" do
    message_from_user1 = Message.create!(
      conversation: @conversation,
      sender: @user1,
      body: "My message",
      read: false
    )
    message_from_user2 = Message.create!(
      conversation: @conversation,
      sender: @user2,
      body: "Other message",
      read: false
    )

    get "/api/v1/conversations/#{@conversation.id}/messages", headers: auth_headers(@token1)

    assert_response :success
    message_from_user1.reload
    message_from_user2.reload
    assert_equal false, message_from_user1.read
    assert_equal true, message_from_user2.read
  end

  test "should not get messages for non-existent conversation" do
    get "/api/v1/conversations/99999/messages", headers: auth_headers(@token1)

    assert_response :not_found
    json_response = JSON.parse(response.body)
    assert_equal "Conversation not found", json_response["error"]
  end

  test "should create message with valid body" do
    assert_difference "Message.count", 1 do
      post "/api/v1/conversations/#{@conversation.id}/messages",
           params: { body: "New message" },
           headers: auth_headers(@token1)
    end

    assert_response :created
    json_response = JSON.parse(response.body)
    assert json_response["id"].present?
    assert_equal "New message", json_response["body"]
    assert_equal @user1.id, json_response["sender"]["id"]
    assert_equal "Message sent successfully", json_response["message"]
  end

  test "should create message and mark conversation as unread" do
    @conversation.update(read: true)

    post "/api/v1/conversations/#{@conversation.id}/messages",
         params: { body: "New message" },
         headers: auth_headers(@token1)

    assert_response :created
    @conversation.reload
    assert_equal false, @conversation.read
  end

  test "should not create message without body" do
    assert_no_difference "Message.count" do
      post "/api/v1/conversations/#{@conversation.id}/messages",
           params: {},
           headers: auth_headers(@token1)
    end

    assert_response :unprocessable_entity
    json_response = JSON.parse(response.body)
    assert_equal "Message body is required", json_response["error"]
  end

  test "should not create message with empty body" do
    assert_no_difference "Message.count" do
      post "/api/v1/conversations/#{@conversation.id}/messages",
           params: { body: "" },
           headers: auth_headers(@token1)
    end

    assert_response :unprocessable_entity
    json_response = JSON.parse(response.body)
    assert_equal "Message body is required", json_response["error"]
  end

  test "should not create message for non-existent conversation" do
    assert_no_difference "Message.count" do
      post "/api/v1/conversations/99999/messages",
           params: { body: "Test message" },
           headers: auth_headers(@token1)
    end

    assert_response :not_found
    json_response = JSON.parse(response.body)
    assert_equal "Conversation not found", json_response["error"]
  end

  test "should include read status in created message response" do
    post "/api/v1/conversations/#{@conversation.id}/messages",
         params: { body: "Test message" },
         headers: auth_headers(@token1)

    assert_response :created
    json_response = JSON.parse(response.body)
    assert_equal false, json_response["read"]
  end

  test "should include created_at in created message response" do
    post "/api/v1/conversations/#{@conversation.id}/messages",
         params: { body: "Test message" },
         headers: auth_headers(@token1)

    assert_response :created
    json_response = JSON.parse(response.body)
    assert json_response["created_at"].present?
  end

  test "should require authentication for index" do
    get "/api/v1/conversations/#{@conversation.id}/messages"

    assert_response :unauthorized
  end

  test "should require authentication for create" do
    post "/api/v1/conversations/#{@conversation.id}/messages",
         params: { body: "Test message" }

    assert_response :unauthorized
  end

  test "should return sender information in created message" do
    post "/api/v1/conversations/#{@conversation.id}/messages",
         params: { body: "Test message" },
         headers: auth_headers(@token1)

    assert_response :created
    json_response = JSON.parse(response.body)
    sender = json_response["sender"]
    assert_equal @user1.id, sender["id"]
    assert_equal @user1.username, sender["username"]
    assert_equal @user1.first_name, sender["first_name"]
    assert_equal @user1.last_name, sender["last_name"]
  end
end
