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
    assert_equal true, timer_run["active"]
    assert_equal false, timer_run["paused"]
    assert_equal "sleeping", timer_run["run_type"]
    assert_equal({}, timer_run["metadata"])

    assert @user1.timer_runs.find(timer_run["id"]).active?
  end

  test "active returns null when no active run" do
    get "/api/v1/timer_runs/active", headers: auth_headers(@token1)

    assert_response :success
    json_response = JSON.parse(response.body)

    assert_nil json_response["timer_run"]
  end

  test "active returns current users active run" do
    timer_run = @user1.timer_runs.create!(
      start_time: 1.hour.ago,
      submitted: false,
      active: true,
      paused: false
    )
    @user2.timer_runs.create!(
      start_time: 2.hours.ago,
      submitted: false,
      active: true
    )

    get "/api/v1/timer_runs/active", headers: auth_headers(@token1)

    assert_response :success
    json_response = JSON.parse(response.body)
    active = json_response["timer_run"]

    assert_equal timer_run.id, active["id"]
    assert_equal false, active["paused"]
    assert_equal true, active["active"]
  end

  test "pause sets paused and end_time while keeping active" do
    timer_run = @user1.timer_runs.create!(
      start_time: 2.hours.ago,
      submitted: false,
      active: true,
      paused: false
    )
    end_time = 1.hour.ago.iso8601

    patch "/api/v1/timer_runs/#{timer_run.id}",
          params: { paused: true, end_time: end_time },
          headers: auth_headers(@token1)

    assert_response :success
    json_response = JSON.parse(response.body)
    updated = json_response["timer_run"]

    assert_equal true, updated["paused"]
    assert_equal end_time, updated["end_time"]
    assert_equal true, updated["active"]

    timer_run.reload
    assert timer_run.paused?
    assert timer_run.active?
    assert timer_run.end_time.present?
  end

  test "resume clears paused and end_time while keeping active" do
    timer_run = @user1.timer_runs.create!(
      start_time: 2.hours.ago,
      end_time: 1.hour.ago,
      submitted: false,
      active: true,
      paused: true
    )

    patch "/api/v1/timer_runs/#{timer_run.id}",
          params: { paused: false },
          headers: auth_headers(@token1)

    assert_response :success
    json_response = JSON.parse(response.body)
    updated = json_response["timer_run"]

    assert_equal false, updated["paused"]
    assert_nil updated["end_time"]
    assert_equal true, updated["active"]

    timer_run.reload
    assert_not timer_run.paused?
    assert_nil timer_run.end_time
    assert timer_run.active?
  end

  test "pause requires end_time" do
    timer_run = @user1.timer_runs.create!(
      start_time: 2.hours.ago,
      submitted: false,
      active: true
    )

    patch "/api/v1/timer_runs/#{timer_run.id}",
          params: { paused: true },
          headers: auth_headers(@token1)

    assert_response :unprocessable_entity
    json_response = JSON.parse(response.body)

    assert_equal "end_time is required when pausing", json_response["error"]
  end

  test "second create auto-closes active run without end_time" do
    first_start = 2.hours.ago.iso8601
    second_start = 1.hour.ago.iso8601

    post "/api/v1/timer_runs",
         params: { start_time: first_start },
         headers: auth_headers(@token1)
    assert_response :created
    first_run = @user1.timer_runs.order(:id).first

    travel_to Time.zone.parse(second_start) do
      assert_difference -> { @user1.timer_runs.count }, 1 do
        post "/api/v1/timer_runs",
             params: { start_time: second_start },
             headers: auth_headers(@token1)
      end
    end

    assert_response :created
    first_run.reload
    second_run = @user1.timer_runs.active.first

    assert_not first_run.active?
    assert first_run.end_time.present?
    assert_in_delta Time.zone.parse(second_start).to_f, first_run.end_time.to_f, 1.0
    assert second_run.active?
    assert_equal Time.zone.parse(second_start), second_run.start_time
  end

  test "second create deactivates prior active run that already has end_time" do
    existing_end = 90.minutes.ago
    first_run = @user1.timer_runs.create!(
      start_time: 2.hours.ago,
      end_time: existing_end,
      active: true,
      submitted: false
    )
    second_start = 1.hour.ago.iso8601

    post "/api/v1/timer_runs",
         params: { start_time: second_start },
         headers: auth_headers(@token1)

    assert_response :created
    first_run.reload

    assert_not first_run.active?
    assert_equal existing_end.to_i, first_run.end_time.to_i
    assert @user1.timer_runs.active.exists?
  end

  test "update sets end_time duration and submitted" do
    timer_run = @user1.timer_runs.create!(
      start_time: 2.hours.ago,
      submitted: false,
      active: true
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
    assert_equal false, updated["active"]
    assert_equal false, updated["paused"]

    timer_run.reload
    assert timer_run.submitted?
    assert_equal 3_600_000, timer_run.duration
    assert_not timer_run.active?
  end

  test "update rejects end_time before start_time" do
    start_time = Time.zone.parse("2026-06-01 12:00:00")
    timer_run = @user1.timer_runs.create!(
      start_time: start_time,
      submitted: false,
      active: true
    )

    patch "/api/v1/timer_runs/#{timer_run.id}",
          params: {
            end_time: (start_time - 1.minute).iso8601,
            duration: 60_000,
            submitted: true
          },
          headers: auth_headers(@token1)

    assert_response :unprocessable_entity
    json_response = JSON.parse(response.body)
    assert_includes json_response["errors"], "End time must be after start time"
    assert_not timer_run.reload.submitted?
  end

  test "create rejects start_time in the future" do
    future_start = 1.hour.from_now.iso8601

    assert_no_difference -> { @user1.timer_runs.count } do
      post "/api/v1/timer_runs",
           params: { start_time: future_start },
           headers: auth_headers(@token1)
    end

    assert_response :unprocessable_entity
    json_response = JSON.parse(response.body)
    assert_includes json_response["errors"], "Start time cannot be in the future"
  end

  test "update rejects start_time in the future" do
    timer_run = @user1.timer_runs.create!(
      start_time: 2.hours.ago,
      submitted: false,
      active: true
    )
    future_start = 1.hour.from_now

    patch "/api/v1/timer_runs/#{timer_run.id}",
          params: {
            start_time: future_start.iso8601,
            end_time: (future_start + 30.minutes).iso8601,
            duration: 1_800_000,
            submitted: true
          },
          headers: auth_headers(@token1)

    assert_response :unprocessable_entity
    json_response = JSON.parse(response.body)
    assert_includes json_response["errors"], "Start time cannot be in the future"
    assert_not timer_run.reload.submitted?
  end

  test "index filters by from and to range overlap" do
    in_range = @user1.timer_runs.create!(
      start_time: Time.zone.parse("2026-05-28 10:00:00"),
      end_time: Time.zone.parse("2026-05-28 11:00:00"),
      duration: 3_600_000,
      submitted: true
    )
    @user1.timer_runs.create!(
      start_time: Time.zone.parse("2026-05-20 10:00:00"),
      end_time: Time.zone.parse("2026-05-20 11:00:00"),
      duration: 3_600_000,
      submitted: true
    )
    spanning_midnight = @user1.timer_runs.create!(
      start_time: Time.zone.parse("2026-05-27 23:30:00"),
      end_time: Time.zone.parse("2026-05-28 00:30:00"),
      duration: 3_600_000,
      submitted: true
    )

    get "/api/v1/timer_runs",
        params: { from: "2026-05-26", to: "2026-06-01" },
        headers: auth_headers(@token1)

    assert_response :success
    json_response = JSON.parse(response.body)
    ids = json_response["timer_runs"].map { |run| run["id"] }

    assert_equal [spanning_midnight.id, in_range.id], ids
  end

  test "index without range params returns all submitted runs newest first" do
    older = @user1.timer_runs.create!(
      start_time: 3.hours.ago,
      end_time: 2.hours.ago,
      duration: 3_600_000,
      submitted: true
    )
    newer = @user1.timer_runs.create!(
      start_time: 1.hour.ago,
      end_time: 30.minutes.ago,
      duration: 1_800_000,
      submitted: true
    )

    get "/api/v1/timer_runs", headers: auth_headers(@token1)

    assert_response :success
    json_response = JSON.parse(response.body)
    ids = json_response["timer_runs"].map { |run| run["id"] }

    assert_equal [newer.id, older.id], ids
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

  test "destroy removes own timer run" do
    timer_run = @user1.timer_runs.create!(
      start_time: 2.hours.ago,
      end_time: 1.hour.ago,
      duration: 3_600_000,
      submitted: true
    )

    assert_difference -> { @user1.timer_runs.count }, -1 do
      delete "/api/v1/timer_runs/#{timer_run.id}",
             headers: auth_headers(@token1)
    end

    assert_response :no_content
    assert_not TimerRun.exists?(timer_run.id)
  end

  test "destroy removes active in-progress timer run" do
    timer_run = @user1.timer_runs.create!(
      start_time: 30.minutes.ago,
      submitted: false,
      active: true,
      paused: false,
      run_type: "sleeping"
    )

    assert_difference -> { @user1.timer_runs.count }, -1 do
      delete "/api/v1/timer_runs/#{timer_run.id}",
             headers: auth_headers(@token1)
    end

    assert_response :no_content
    assert_not TimerRun.exists?(timer_run.id)
    assert_nil @user1.timer_runs.active.first
  end

  test "destroy removes paused active timer run" do
    timer_run = @user1.timer_runs.create!(
      start_time: 30.minutes.ago,
      end_time: 5.minutes.ago,
      submitted: false,
      active: true,
      paused: true,
      run_type: "nursing_left"
    )

    assert_difference -> { @user1.timer_runs.count }, -1 do
      delete "/api/v1/timer_runs/#{timer_run.id}",
             headers: auth_headers(@token1)
    end

    assert_response :no_content
    assert_not TimerRun.exists?(timer_run.id)
  end

  test "cannot destroy another users timer run" do
    timer_run = @user2.timer_runs.create!(
      start_time: 2.hours.ago,
      end_time: 1.hour.ago,
      duration: 3_600_000,
      submitted: true
    )

    assert_no_difference -> { TimerRun.count } do
      delete "/api/v1/timer_runs/#{timer_run.id}",
             headers: auth_headers(@token1)
    end

    assert_response :not_found
  end

  test "create with nursing_left run_type" do
    start_time = 1.hour.ago.iso8601

    post "/api/v1/timer_runs",
         params: { start_time: start_time, run_type: "nursing_left" },
         headers: auth_headers(@token1)

    assert_response :created
    timer_run = JSON.parse(response.body)["timer_run"]

    assert_equal "nursing_left", timer_run["run_type"]
    assert_equal true, timer_run["active"]
  end

  test "create bottle submitted in one request" do
    start_time = Time.zone.parse("2026-06-01 22:29:00").iso8601
    metadata = {
      "feeding_type" => "formula",
      "unit" => "oz",
      "amount" => 4,
      "notes" => "after nap"
    }

    assert_difference -> { @user1.timer_runs.count }, 1 do
      post "/api/v1/timer_runs",
           params: {
             start_time: start_time,
             run_type: "bottle",
             submitted: true,
             metadata: metadata
           },
           headers: auth_headers(@token1)
    end

    assert_response :created
    timer_run = JSON.parse(response.body)["timer_run"]

    assert_equal "bottle", timer_run["run_type"]
    assert_equal true, timer_run["submitted"]
    assert_equal false, timer_run["active"]
    assert_equal start_time, timer_run["end_time"]
    assert_equal 0, timer_run["duration"]
    assert_equal "formula", timer_run["metadata"]["feeding_type"]
    assert_equal 4, timer_run["metadata"]["amount"].to_i

    record = @user1.timer_runs.find(timer_run["id"])
    assert_not record.active?
  end

  test "index filters by run_type" do
    nap = @user1.timer_runs.create!(
      start_time: 3.hours.ago,
      end_time: 2.hours.ago,
      duration: 3_600_000,
      submitted: true,
      run_type: :sleeping
    )
    @user1.timer_runs.create!(
      start_time: 3.hours.ago,
      end_time: 2.hours.ago,
      duration: 0,
      submitted: true,
      run_type: :bottle,
      metadata: { "unit" => "oz" }
    )

    get "/api/v1/timer_runs",
        params: { run_type: "sleeping" },
        headers: auth_headers(@token1)

    assert_response :success
    ids = JSON.parse(response.body)["timer_runs"].map { |run| run["id"] }

    assert_equal [nap.id], ids
  end

  test "active filters by run_type" do
    @user1.timer_runs.create!(
      start_time: 2.hours.ago,
      submitted: false,
      active: true,
      run_type: :nursing_left
    )

    get "/api/v1/timer_runs/active",
        params: { run_type: "nursing_right" },
        headers: auth_headers(@token1)

    assert_response :success
    assert_nil JSON.parse(response.body)["timer_run"]

    get "/api/v1/timer_runs/active",
        params: { run_type: "nursing_left" },
        headers: auth_headers(@token1)

    assert_response :success
    assert_not_nil JSON.parse(response.body)["timer_run"]
  end

  test "create rejects invalid run_type" do
    post "/api/v1/timer_runs",
         params: { start_time: 1.hour.ago.iso8601, run_type: "invalid" },
         headers: auth_headers(@token1)

    assert_response :unprocessable_entity
    assert_equal "invalid run_type", JSON.parse(response.body)["error"]
  end
end
