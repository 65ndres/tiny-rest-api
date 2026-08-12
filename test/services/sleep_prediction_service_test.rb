# frozen_string_literal: true

require "test_helper"

class SleepPredictionServiceTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(
      email: "sleep_pred@example.com",
      password: "password123",
      password_confirmation: "password123",
      username: "sleeppreduser",
      first_name: "Sleep",
      last_name: "Parent",
      # Fixed date so age is exactly 6 months on the 2026-07-08 fixtures below.
      baby_birthdate: Date.new(2026, 1, 8),
      daily_nap_count: 3
    )
  end

  def predict_at(now, submitted_runs: [], active_run: nil)
    SleepPredictionService.new(
      @user,
      submitted_runs: submitted_runs,
      active_run: active_run,
      now: now
    ).predict
  end

  def create_submitted_sleep(start_time:, end_time:)
    @user.timer_runs.create!(
      start_time: start_time,
      end_time: end_time,
      duration: ((end_time - start_time) * 1000).to_i,
      submitted: true,
      active: false,
      run_type: :sleeping
    )
  end

  test "returns needs_birthdate when baby_birthdate is missing" do
    @user.update!(baby_birthdate: nil)

    result = predict_at(Time.zone.parse("2026-07-08 10:00:00"))

    assert_equal "needs_birthdate", result[:status]
    assert_nil result[:predicted_at]
  end

  test "base_wake_window_minutes maps age brackets" do
    assert_equal 48, SleepPredictionService.base_wake_window_minutes(0)
    assert_equal 75, SleepPredictionService.base_wake_window_minutes(2)
    assert_equal 98, SleepPredictionService.base_wake_window_minutes(4)
    assert_equal 150, SleepPredictionService.base_wake_window_minutes(6)
    assert_equal 180, SleepPredictionService.base_wake_window_minutes(9)
    assert_equal 210, SleepPredictionService.base_wake_window_minutes(12)
    assert_equal 300, SleepPredictionService.base_wake_window_minutes(18)
    assert_equal 330, SleepPredictionService.base_wake_window_minutes(30)
  end

  test "progressive wake windows use shortest morning and longest pre-bedtime for 3 naps" do
    base = 150
    assert_equal 128, SleepPredictionService.wake_window_for_slot(0, 3, base)
    assert_equal 150, SleepPredictionService.wake_window_for_slot(1, 3, base)
    assert_equal 150, SleepPredictionService.wake_window_for_slot(2, 3, base)
    assert_equal 180, SleepPredictionService.wake_window_for_slot(3, 3, base)
  end

  test "progressive wake windows reverse for 1 nap schedule" do
    base = 300
    assert_equal 360, SleepPredictionService.wake_window_for_slot(0, 1, base)
    assert_equal 255, SleepPredictionService.wake_window_for_slot(1, 1, base)
  end

  test "active daytime sleep returns currently_napping" do
    now = Time.zone.parse("2026-07-08 14:00:00")
    active_run = @user.timer_runs.create!(
      start_time: now - 30.minutes,
      submitted: false,
      active: true,
      run_type: :sleeping
    )

    result = predict_at(now, active_run: active_run)

    assert_equal "currently_napping", result[:status]
    assert_nil result[:predicted_at]
    assert_equal 30, result[:active_sleep][:elapsed_minutes]
  end

  test "active night sleep returns currently_sleeping" do
    now = Time.zone.parse("2026-07-08 23:00:00")
    active_run = @user.timer_runs.create!(
      start_time: Time.zone.parse("2026-07-08 22:15:00"),
      submitted: false,
      active: true,
      run_type: :sleeping
    )

    result = predict_at(now, active_run: active_run)

    assert_equal "currently_sleeping", result[:status]
    assert_nil result[:predicted_at]
    assert_equal 45, result[:active_sleep][:elapsed_minutes]
  end

  test "night_sleep? respects user day window" do
    run = @user.timer_runs.new(start_time: Time.zone.parse("2026-07-08 20:00:00"))

    refute SleepPredictionService.night_sleep?(
      run,
      day_start_minutes: 570,
      day_end_minutes: 1320
    )
    assert SleepPredictionService.night_sleep?(
      run,
      day_start_minutes: 570,
      day_end_minutes: 1140
    )
  end

  test "next nap before day-end stays next_nap" do
    now = Time.zone.parse("2026-07-08 16:00:00")
    @user.update!(day_end_minutes: 1320) # 10:00 PM
    nap = create_submitted_sleep(
      start_time: Time.zone.parse("2026-07-08 14:00:00"),
      end_time: Time.zone.parse("2026-07-08 15:00:00")
    )

    result = predict_at(now, submitted_runs: [nap])

    assert_equal "next_nap", result[:status]
    expected = Time.zone.parse("2026-07-08 17:30:00") # 15:00 + 150
    assert_equal expected.iso8601, result[:predicted_at]
  end

  test "predicted next nap on or after day-end becomes bedtime" do
    now = Time.zone.parse("2026-07-08 18:00:00")
    @user.update!(day_end_minutes: 1140) # 7:00 PM
    nap = create_submitted_sleep(
      start_time: Time.zone.parse("2026-07-08 16:00:00"),
      end_time: Time.zone.parse("2026-07-08 17:00:00")
    )

    result = predict_at(now, submitted_runs: [nap])

    assert_equal "bedtime", result[:status]
    assert_equal 180, result[:wake_window_minutes]
    expected = Time.zone.parse("2026-07-08 20:00:00") # 17:00 + bedtime slot 180
    assert_equal expected.iso8601, result[:predicted_at]
  end

  test "predicts next nap using shortest morning wake window after overnight wake" do
    now = Time.zone.parse("2026-07-08 08:00:00")
    overnight = create_submitted_sleep(
      start_time: Time.zone.parse("2026-07-07 20:00:00"),
      end_time: Time.zone.parse("2026-07-08 07:00:00")
    )

    result = predict_at(now, submitted_runs: [overnight])

    assert_equal "next_nap", result[:status]
    assert_equal 0, result[:naps_today]
    assert_equal 128, result[:wake_window_minutes]
    expected = Time.zone.parse("2026-07-08 09:08:00")
    assert_equal expected.iso8601, result[:predicted_at]
  end

  test "predicts bedtime after daily nap count is met" do
    now = Time.zone.parse("2026-07-08 16:00:00")
    nap1 = create_submitted_sleep(
      start_time: Time.zone.parse("2026-07-08 09:30:00"),
      end_time: Time.zone.parse("2026-07-08 10:30:00")
    )
    nap2 = create_submitted_sleep(
      start_time: Time.zone.parse("2026-07-08 12:45:00"),
      end_time: Time.zone.parse("2026-07-08 13:30:00")
    )
    nap3 = create_submitted_sleep(
      start_time: Time.zone.parse("2026-07-08 15:00:00"),
      end_time: Time.zone.parse("2026-07-08 15:45:00")
    )

    result = predict_at(now, submitted_runs: [nap1, nap2, nap3])

    assert_equal "bedtime", result[:status]
    assert_equal 3, result[:naps_today]
    assert_equal 180, result[:wake_window_minutes]
    expected = Time.zone.parse("2026-07-08 18:45:00")
    assert_equal expected.iso8601, result[:predicted_at]
  end

  test "does not count overnight sleep as a nap today" do
    now = Time.zone.parse("2026-07-08 08:30:00")
    overnight = create_submitted_sleep(
      start_time: Time.zone.parse("2026-07-07 20:00:00"),
      end_time: Time.zone.parse("2026-07-08 07:00:00")
    )

    result = predict_at(now, submitted_runs: [overnight])

    assert_equal 0, result[:naps_today]
    assert_equal "next_nap", result[:status]
  end
end
