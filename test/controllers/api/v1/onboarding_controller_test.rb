require "test_helper"

class Api::V1::OnboardingControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(
      email: "onboarding@example.com",
      password: "password123",
      password_confirmation: "password123",
      username: "onboarding_user"
    )
    @token = Warden::JWTAuth::UserEncoder.new.call(@user, :user, nil).first
  end

  def auth_headers(token)
    { "Authorization" => "Bearer #{token}" }
  end

  test "show returns onboarding progress" do
    get "/api/v1/onboarding", headers: auth_headers(@token)

    assert_response :success
    body = JSON.parse(response.body)
    assert_nil body.dig("onboarding", "last_completed_step")
    assert_nil body.dig("onboarding", "completed_at")
    assert_includes body.dig("onboarding", "allowed_steps"), "baby_profile"
  end

  test "update persists last_completed_step" do
    patch "/api/v1/onboarding",
          params: { last_completed_step: "baby_profile" },
          headers: auth_headers(@token)

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal "baby_profile", body.dig("onboarding", "last_completed_step")
    assert_equal "baby_profile", @user.onboarding.reload.last_completed_step
  end

  test "update rejects unknown step" do
    patch "/api/v1/onboarding",
          params: { last_completed_step: "not_a_real_step" },
          headers: auth_headers(@token)

    assert_response :unprocessable_entity
    body = JSON.parse(response.body)
    assert_equal "Invalid onboarding step", body["error"]
  end

  test "requires authentication" do
    get "/api/v1/onboarding"
    assert_response :unauthorized
  end
end
