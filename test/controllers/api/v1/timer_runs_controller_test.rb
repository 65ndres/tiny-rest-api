# frozen_string_literal: true

require "test_helper"

class Api::V1::TimerRunsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user1 = User.create!(
      email: "timer1@example.com",
      password: "password123",
      password_confirmation: "password123",
      username: "timeruser1",
      first_name: "John",
      last_name: "Doe"
    )
    @user2 = User.create!(
      email: "timer2@example.com",
      password: "password123",
      password_confirmation: "password123",
      username: "timeruser2",
      first_name: "Jane",
      last_name: "Smith"
    )

    @token1 = Warden::JWTAuth::UserEncoder.new.call(@user1, :user, nil).first
    @token2 = Warden::JWTAuth::UserEncoder.new.call(@user2, :user, nil).first
  end

  def auth_headers(token)
    { "Authorization" => "Bearer #{token}" }
  end

  test "index requires authentication" do
    get "/api/v1/timer_runs"

    assert_response :unauthorized
  end

  test "create returns timer run with submitted false" do
    start_time = 1.hour.ago.iso8601

    assert_difference -> { @user1.timer_runs.count }, 1 do
      post "/api/v1/timer_runs",
           params: { start_time: start_time },
           headers: auth_headers(@token1)
    end

    assert_response :created
    json_response = JSON.parse(response.body)
    timer_run = json_response["timer_run"]

    assert timer_run["id"].present?
    assert_equal start_time, timer_run["start_time"]
    assert_nil timer_run["end_time"]
    assert_nil timer_run["duration"]
    assert_equal false, timer_run["submitted"]
  end

  test "update sets end_time duration and submitted" do
    timer_run = @user1.timer_runs.create!(
      start_time: 2.hours.ago,
      submitted: false
    )
    end_time = 1.hour.ago.iso8601

    patch "/api/v1/timer_runs/#{timer_run.id}",
          params: {
            end_time: end_time,
            duration: 3_600_000,
            submitted: true
          },
          headers: auth_headers(@token1)

    assert_response :success
    json_response = JSON.parse(response.body)
    updated = json_response["timer_run"]

    assert_equal end_time, updated["end_time"]
    assert_equal 3_600_000, updated["duration"]
    assert_equal true, updated["submitted"]

    timer_run.reload
    assert timer_run.submitted?
    assert_equal 3_600_000, timer_run.duration
  end

  test "index returns only current user submitted runs" do
    submitted_run = @user1.timer_runs.create!(
      start_time: 3.hours.ago,
      end_time: 2.hours.ago,
      duration: 3_600_000,
      submitted: true
    )
    @user1.timer_runs.create!(
      start_time: 1.hour.ago,
      submitted: false
    )
    @user2.timer_runs.create!(
      start_time: 4.hours.ago,
      end_time: 3.hours.ago,
      duration: 3_600_000,
      submitted: true
    )

    get "/api/v1/timer_runs", headers: auth_headers(@token1)

    assert_response :success
    json_response = JSON.parse(response.body)
    ids = json_response["timer_runs"].map { |run| run["id"] }

    assert_equal [submitted_run.id], ids
  end

  test "cannot update another users timer run" do
    timer_run = @user2.timer_runs.create!(
      start_time: 2.hours.ago,
      submitted: false
    )

    patch "/api/v1/timer_runs/#{timer_run.id}",
          params: {
            end_time: 1.hour.ago.iso8601,
            duration: 1_000,
            submitted: true
          },
          headers: auth_headers(@token1)

    assert_response :not_found
  end
end
