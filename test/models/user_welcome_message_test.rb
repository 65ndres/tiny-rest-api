require "test_helper"

class UserWelcomeMessageTest < ActiveSupport::TestCase
  setup do
    @support = users(:support)
  end

  test "creating a user opens a support conversation with a welcome message" do
    user = nil

    assert_difference -> { Conversation.support.count }, 1 do
      assert_difference -> { Message.count }, 1 do
        user = User.create!(
          email: "welcome_user@example.com",
          password: "password123",
          password_confirmation: "password123",
          username: "welcome_user"
        )
      end
    end

    conversation = Conversation.find_or_create_support_for!(user)
    welcome = conversation.messages.order(:created_at).first

    assert_equal @support, welcome.sender
    assert_equal User::WELCOME_MESSAGE_BODY, welcome.body
    assert_includes conversation.users, user
    assert_includes conversation.users, @support
  end

  test "support account does not receive a welcome conversation" do
    assert_no_difference -> { Conversation.support.count } do
      # Fixture already exists; creating another support-like user by email is unique.
      # Ensure callback no-ops for the fixture support identity.
      @support.send(:send_welcome_message)
    end
  end
end
