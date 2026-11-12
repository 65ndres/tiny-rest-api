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
    assert_match(/Only the Support account can sign in here/, response.body)
  end

  test "wrong password is rejected" do
    post admin_login_path, params: {
      email: @support.email,
      password: "wrong-password"
    }

    assert_response :unprocessable_entity
  end

  test "sign out button logs the support user out" do
    post admin_login_path, params: { email: @support.email, password: "password123" }

    # button_to sends a POST with a hidden _method=delete field, like a browser does.
    post admin_logout_path, params: { _method: "delete" }

    assert_redirected_to admin_login_path
    get admin_root_path
    assert_redirected_to admin_login_path
  end
end
