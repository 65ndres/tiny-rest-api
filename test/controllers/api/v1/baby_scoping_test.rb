# frozen_string_literal: true

require "test_helper"

# Timer runs, the active timer, sleep prediction and /user follow the baby the
# client selects with the X-Baby-Id header.
class Api::V1::BabyScopingTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(
      email: "scoping@example.com",
      password: "password123",
      password_confirmation: "password123",
      baby_name: "Ana",
      baby_birthdate: 8.months.ago.to_date,
      daily_nap_count: 2
    )
    @ana = @user.babies.first
    @bo = @user.babies.create!(name: "Bo", birthdate: 3.months.ago.to_date, daily_nap_count: 4)
    @other = User.create!(email: "scoping_other@example.com", password: "password123")
    @token = Warden::JWTAuth::UserEncoder.new.call(@user, :user, nil).first
  end

  def headers_for(baby = nil)
    headers = { "Authorization" => "Bearer #{@token}" }
    headers["X-Baby-Id"] = baby.id.to_s if baby
    headers
  end

  def json
    JSON.parse(response.body)
  end

  def finished_run(baby, hours_ago:)
    @user.timer_runs.create!(baby: baby, start_time: hours_ago.hours.ago,
                             end_time: (hours_ago - 1).hours.ago, duration: 3_600_000, submitted: true)
  end

  test "index returns only the selected baby's runs" do
    ana_run = finished_run(@ana, hours_ago: 3)
    bo_run = finished_run(@bo, hours_ago: 3)

    get "/api/v1/timer_runs", headers: headers_for(@bo)
    assert_equal [ bo_run.id ], json["timer_runs"].map { |r| r["id"] }
    assert_equal @bo.id, json["timer_runs"].first["baby_id"]

    get "/api/v1/timer_runs", headers: headers_for(@ana)
    assert_equal [ ana_run.id ], json["timer_runs"].map { |r| r["id"] }
  end

  test "without a header requests use the first baby" do
    ana_run = finished_run(@ana, hours_ago: 3)
    finished_run(@bo, hours_ago: 3)

    get "/api/v1/timer_runs", headers: headers_for

    assert_equal [ ana_run.id ], json["timer_runs"].map { |r| r["id"] }
  end

  test "an unknown or foreign baby id falls back to the first baby" do
    ana_run = finished_run(@ana, hours_ago: 3)

    get "/api/v1/timer_runs", headers: headers_for(@other.primary_baby)

    assert_equal [ ana_run.id ], json["timer_runs"].map { |r| r["id"] }
  end

  test "create attaches new runs to the selected baby" do
    post "/api/v1/timer_runs", params: { start_time: 10.minutes.ago.iso8601 }, headers: headers_for(@bo)

    assert_response :created
    assert_equal @bo.id, TimerRun.find(json["timer_run"]["id"]).baby_id
  end

  test "bottle feedings attach to the selected baby" do
    post "/api/v1/timer_runs",
         params: { start_time: 10.minutes.ago.iso8601, run_type: "bottle", submitted: true },
         headers: headers_for(@bo)

    assert_response :created
    assert_equal @bo.id, json["timer_run"]["baby_id"]
  end

  test "active is per baby unless all_babies is set" do
    run = @user.timer_runs.create!(baby: @ana, start_time: 10.minutes.ago, run_type: :nursing_left)

    get "/api/v1/timer_runs/active", headers: headers_for(@bo)
    assert_nil json["timer_run"]

    get "/api/v1/timer_runs/active", headers: headers_for(@ana)
    assert_equal run.id, json["timer_run"]["id"]

    get "/api/v1/timer_runs/active", params: { all_babies: true }, headers: headers_for(@bo)
    assert_equal run.id, json["timer_run"]["id"]
    assert_equal @ana.id, json["timer_run"]["baby_id"]
  end

  test "a running timer can be submitted after switching to another baby" do
    run = @user.timer_runs.create!(baby: @ana, start_time: 30.minutes.ago)
    end_time = Time.current

    patch "/api/v1/timer_runs/#{run.id}",
          params: { end_time: end_time.iso8601, duration: 30 * 60 * 1000, submitted: true },
          headers: headers_for(@bo)

    assert_response :success
    run.reload
    assert run.submitted
    refute run.active
    assert_equal @ana.id, run.baby_id
  end

  test "twins can have overlapping entries" do
    finished_run(@ana, hours_ago: 3)

    post "/api/v1/timer_runs",
         params: { start_time: 3.hours.ago.iso8601, run_type: "bottle", submitted: true },
         headers: headers_for(@bo)

    assert_response :created
  end

  test "sleep prediction uses the selected baby's profile and naps" do
    travel_to Time.zone.parse("2026-07-08 10:00:00") do
      get "/api/v1/sleep_prediction", headers: headers_for(@bo)
      assert_response :success
      assert_equal 4, json["daily_nap_count"]

      get "/api/v1/sleep_prediction", headers: headers_for(@ana)
      assert_equal 2, json["daily_nap_count"]
    end
  end

  test "sleep prediction ignores another baby's running sleep" do
    @user.timer_runs.create!(baby: @ana, start_time: 10.minutes.ago)

    get "/api/v1/sleep_prediction", headers: headers_for(@bo)
    assert_nil json["active_sleep"]

    get "/api/v1/sleep_prediction", headers: headers_for(@ana)
    assert json["active_sleep"].present?
  end

  test "user profile shows and updates the selected baby" do
    get "/api/v1/user", headers: headers_for(@bo)
    assert_equal @bo.id, json["baby_id"]
    assert_equal "Bo", json["baby_name"]
    assert_equal 4, json["daily_nap_count"]

    patch "/api/v1/user",
          params: { user: { first_name: "Pat", daily_nap_count: 3 } },
          headers: headers_for(@bo)

    assert_response :success
    assert_equal 3, @bo.reload.daily_nap_count
    assert_equal 2, @ana.reload.daily_nap_count
    assert_equal "Pat", @user.reload.first_name
  end

  test "invalid baby fields on /user return errors and save nothing" do
    patch "/api/v1/user",
          params: { user: { first_name: "Pat", baby_birthdate: (Date.current + 3.days).iso8601 } },
          headers: headers_for(@bo)

    assert_response :unprocessable_entity
    assert_includes json["errors"], "Baby birthdate must be in the past"
    assert_not_equal "Pat", @user.reload.first_name
  end
end
