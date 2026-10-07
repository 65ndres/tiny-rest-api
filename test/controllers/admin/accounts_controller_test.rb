# frozen_string_literal: true

require "test_helper"

class Admin::AccountsControllerTest < ActionDispatch::IntegrationTest
  include ActiveSupport::Testing::TimeHelpers

  setup do
    @support = users(:support)
  end

  test "requires a support login" do
    get new_admin_account_path

    assert_redirected_to admin_login_path
  end

  test "creates a login-ready pro account" do
    sign_in_support!
    travel_to Time.find_zone!("America/New_York").parse("2026-10-06 15:00:00") do
      assert_difference -> { User.count }, 1 do
        post admin_accounts_path, params: { daily_nap_count: 3, naps_taken: 2 }
      end
    end

    assert_response :success
    assert_match(/Account ready/, response.body)
    assert_match(/password123/, response.body)
    assert_match(/@example.com/, response.body)

    user = User.order(:id).last
    assert_equal 3, user.daily_nap_count
    assert_equal 2, user.timer_runs.submitted.count
    assert_equal "pro", user.subscription_type_for_payload
    assert user.onboarding.completed_at.present?
  end

  test "shows an error when the nap count is invalid" do
    sign_in_support!

    assert_no_difference -> { User.count } do
      post admin_accounts_path, params: { daily_nap_count: 9, naps_taken: 1 }
    end

    assert_response :unprocessable_entity
    assert_match(/between 0 and 6/, response.body)
  end

  private

  def sign_in_support!
    post admin_login_path, params: {
      email: @support.email,
      password: "password123"
    }
  end
end
