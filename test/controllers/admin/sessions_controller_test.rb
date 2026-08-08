require "test_helper"

class Admin::SessionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @support = users(:support)
    @user = User.create!(
      email: "regular@example.com",
      password: "password123",
      password_confirmation: "password123",
      username: "regular_user"
    )
  end

  test "support user can log in" do
    post admin_login_path, params: {
      email: @support.email,
      password: "password123"
    }

    assert_redirected_to admin_root_path
    follow_redirect!
    assert_response :success
    assert_match(/Conversations/, response.body)
  end

  test "regular user cannot log in to admin" do
    post admin_login_path, params: {
      email: @user.email,
      password: "password123"
    }

    assert_response :unprocessable_entity
    assert_match(/Invalid Support credentials/, response.body)
  end

  test "wrong password is rejected" do
    post admin_login_path, params: {
      email: @support.email,
      password: "wrong-password"
    }

    assert_response :unprocessable_entity
  end
end
