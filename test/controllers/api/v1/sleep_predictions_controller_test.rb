# frozen_string_literal: true

require "test_helper"

class Api::V1::SleepPredictionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(
      email: "sleep_api@example.com",
      password: "password123",
      password_confirmation: "password123",
      username: "sleepapiuser",
      first_name: "Api",
      last_name: "Tester",
      baby_birthdate: 8.months.ago.to_date,
      daily_nap_count: 2
    )

    @token = Warden::JWTAuth::UserEncoder.new.call(@user, :user, nil).first
  end

  def auth_headers(token)
    { "Authorization" => "Bearer #{token}" }
  end

  test "show requires authentication" do
    get "/api/v1/sleep_prediction"

    assert_response :unauthorized
  end

  test "show returns sleep prediction payload" do
    get "/api/v1/sleep_prediction", headers: auth_headers(@token)

    assert_response :success
    json_response = JSON.parse(response.body)

    assert_equal "next_nap", json_response["status"]
    assert json_response.key?("predicted_at")
    assert json_response.key?("wake_window_minutes")
    assert_equal 2, json_response["daily_nap_count"]
    assert_equal 0, json_response["naps_today"]
    assert_nil json_response["active_sleep"]
  end

  test "show returns needs_birthdate when birthdate missing" do
    @user.update!(baby_birthdate: nil)

    get "/api/v1/sleep_prediction", headers: auth_headers(@token)

    assert_response :success
    json_response = JSON.parse(response.body)

    assert_equal "needs_birthdate", json_response["status"]
    assert_nil json_response["predicted_at"]
  end

  test "show returns currently_napping when active daytime sleep exists" do
    @user.timer_runs.create!(
      start_time: Time.zone.parse("2026-07-08 13:00:00"),
      submitted: false,
      active: true,
      run_type: :sleeping
    )

    travel_to Time.zone.parse("2026-07-08 13:40:00") do
      get "/api/v1/sleep_prediction", headers: auth_headers(@token)

      assert_response :success
      json_response = JSON.parse(response.body)

      assert_equal "currently_napping", json_response["status"]
      assert_nil json_response["predicted_at"]
      assert_equal 40, json_response["active_sleep"]["elapsed_minutes"]
    end
  end

  test "show returns range_predictions when alt nap count is set" do
    @user.update!(daily_nap_count: 2, daily_nap_count_alt: 3)

    get "/api/v1/sleep_prediction", headers: auth_headers(@token)

    assert_response :success
    json_response = JSON.parse(response.body)

    assert_equal 2, json_response["daily_nap_count"]
    assert_equal 3, json_response["daily_nap_count_alt"]
    assert_equal 2, json_response["range_predictions"].length
    assert_equal [2, 3], json_response["range_predictions"].map { |prediction| prediction["daily_nap_count"] }
  end
end
