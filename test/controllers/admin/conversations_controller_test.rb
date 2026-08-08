require "test_helper"

class Admin::ConversationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @support = users(:support)
    @customer = User.create!(
      email: "customer@example.com",
      password: "password123",
      password_confirmation: "password123",
      username: "customer_user"
    )

    # Welcome callback may already create a thread; reuse it.
    @conversation = Conversation.find_or_create_support_for!(@customer)
    @conversation.messages.create!(
      body: "Need help with naps",
      sender: @customer
    )

    post admin_login_path, params: {
      email: @support.email,
      password: "password123"
    }
  end

  test "lists support conversations after login" do
    get admin_conversations_path

    assert_response :success
    assert_match(/customer@example.com/, response.body)
    assert_match(/Need help with naps/, response.body)
  end

  test "shows messages and accepts a reply from support" do
    get admin_conversation_path(@conversation)
    assert_response :success
    assert_match(/Need help with naps/, response.body)

    assert_difference -> { @conversation.messages.count }, 1 do
      post admin_conversation_messages_path(@conversation), params: {
        body: "Happy to help — hang in there!"
      }
    end

    assert_redirected_to admin_conversation_path(@conversation)
    follow_redirect!
    assert_match(/Happy to help/, response.body)

    reply = @conversation.messages.order(:created_at).last
    assert_equal @support, reply.sender
    assert_equal "Happy to help — hang in there!", reply.body
  end

  test "requires authentication" do
    delete admin_logout_path
    get admin_conversations_path
    assert_redirected_to admin_login_path
  end
end
