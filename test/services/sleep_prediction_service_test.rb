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
      daily_nap_count: 3,
      day_start_minutes: 420, # 7:00 AM — spreadsheet wake-up
      day_end_minutes: 1320   # 10:00 PM
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
    assert_nil result[:nap_length_minutes]
  end

  test "schedule_for maps spreadsheet age and nap-count variants" do
    assert_equal(
      { naps: 6, wake_window_minutes: 50, nap_length_minutes: 70 },
      SleepPredictionService.schedule_for(0, 6)
    )
    assert_equal(
      { naps: 5, wake_window_minutes: 80, nap_length_minutes: 55 },
      SleepPredictionService.schedule_for(2, 5)
    )
    assert_equal(
      { naps: 3, wake_window_minutes: 110, nap_length_minutes: 75 },
      SleepPredictionService.schedule_for(4, 3)
    )
    assert_equal(
      { naps: 4, wake_window_minutes: 90, nap_length_minutes: 50 },
      SleepPredictionService.schedule_for(5, 4)
    )
    assert_equal(
      { naps: 3, wake_window_minutes: 150, nap_length_minutes: 60 },
      SleepPredictionService.schedule_for(6, 3)
    )
    assert_equal(
      { naps: 2, wake_window_minutes: 180, nap_length_minutes: 90 },
      SleepPredictionService.schedule_for(9, 2)
    )
    assert_equal(
      { naps: 3, wake_window_minutes: 150, nap_length_minutes: 60 },
      SleepPredictionService.schedule_for(9, 3)
    )
    assert_equal(
      { naps: 2, wake_window_minutes: 210, nap_length_minutes: 90 },
      SleepPredictionService.schedule_for(12, 2)
    )
    assert_equal(
      { naps: 1, wake_window_minutes: 300, nap_length_minutes: 120 },
      SleepPredictionService.schedule_for(16, 1)
    )
    assert_equal(
      { naps: 2, wake_window_minutes: 240, nap_length_minutes: 75 },
      SleepPredictionService.schedule_for(16, 2)
    )
    assert_equal(
      { naps: 1, wake_window_minutes: 330, nap_length_minutes: 120 },
      SleepPredictionService.schedule_for(20, 1)
    )
    assert_equal(
      { naps: 1, wake_window_minutes: 330, nap_length_minutes: 90 },
      SleepPredictionService.schedule_for(30, 1)
    )
    assert_equal(
      { naps: 0, wake_window_minutes: 0, nap_length_minutes: 0 },
      SleepPredictionService.schedule_for(40, 0)
    )
    assert_equal(
      { naps: 1, wake_window_minutes: 360, nap_length_minutes: 75 },
      SleepPredictionService.schedule_for(40, 1)
    )
  end

  test "schedule_for uses the closest variant in the age group" do
    # 6-7 months only lists 3 naps.
    closest = SleepPredictionService.schedule_for(6, 2)

    assert_equal 3, closest[:naps]
    assert_equal 150, closest[:wake_window_minutes]
    assert_equal 60, closest[:nap_length_minutes]
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
    assert_equal 60, result[:nap_length_minutes]
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

  test "6-7 month 3-nap schedule starts first nap at 9:30 after 7:00 wake" do
    now = Time.zone.parse("2026-07-08 08:00:00")

    result = predict_at(now, submitted_runs: [])

    assert_equal "next_nap", result[:status]
    assert_equal 0, result[:naps_today]
    assert_equal 150, result[:wake_window_minutes]
    assert_equal 60, result[:nap_length_minutes]
    assert_equal Time.zone.parse("2026-07-08 09:30:00").iso8601, result[:predicted_at]
  end

  test "6-7 month next nap is last wake plus constant wake window" do
    now = Time.zone.parse("2026-07-08 11:00:00")
    nap = create_submitted_sleep(
      start_time: Time.zone.parse("2026-07-08 09:30:00"),
      end_time: Time.zone.parse("2026-07-08 10:30:00")
    )

    result = predict_at(now, submitted_runs: [nap])

    assert_equal "next_nap", result[:status]
    assert_equal 150, result[:wake_window_minutes]
    assert_equal 60, result[:nap_length_minutes]
    assert_equal Time.zone.parse("2026-07-08 13:00:00").iso8601, result[:predicted_at]
  end

  test "8-10 months uses 180 vs 150 wake windows for 2 vs 3 naps" do
    @user.update!(baby_birthdate: Date.new(2025, 10, 8), daily_nap_count: 2)
    now = Time.zone.parse("2026-07-08 08:00:00")

    two_naps = predict_at(now, submitted_runs: [])
    assert_equal 180, two_naps[:wake_window_minutes]
    assert_equal 90, two_naps[:nap_length_minutes]
    assert_equal Time.zone.parse("2026-07-08 10:00:00").iso8601, two_naps[:predicted_at]

    @user.update!(daily_nap_count: 3)
    three_naps = predict_at(now, submitted_runs: [])
    assert_equal 150, three_naps[:wake_window_minutes]
    assert_equal 60, three_naps[:nap_length_minutes]
    assert_equal Time.zone.parse("2026-07-08 09:30:00").iso8601, three_naps[:predicted_at]
  end

  test "14-18 month 1-nap schedule starts at noon after 7:00 wake" do
    @user.update!(baby_birthdate: Date.new(2025, 3, 8), daily_nap_count: 1)
    now = Time.zone.parse("2026-07-08 08:00:00")

    result = predict_at(now, submitted_runs: [])

    assert_equal "next_nap", result[:status]
    assert_equal 300, result[:wake_window_minutes]
    assert_equal 120, result[:nap_length_minutes]
    assert_equal Time.zone.parse("2026-07-08 12:00:00").iso8601, result[:predicted_at]
  end

  test "next nap before day-end stays next_nap" do
    now = Time.zone.parse("2026-07-08 16:00:00")
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
    assert_equal 150, result[:wake_window_minutes]
    expected = Time.zone.parse("2026-07-08 19:00:00") # night cutoff
    assert_equal expected.iso8601, result[:predicted_at]
  end

  test "overnight wake before day start uses day start plus wake window" do
    @user.update!(day_start_minutes: 570) # 9:30 AM
    now = Time.zone.parse("2026-07-08 08:00:00")
    overnight = create_submitted_sleep(
      start_time: Time.zone.parse("2026-07-07 20:00:00"),
      end_time: Time.zone.parse("2026-07-08 07:00:00")
    )

    result = predict_at(now, submitted_runs: [overnight])

    assert_equal "next_nap", result[:status]
    assert_equal 0, result[:naps_today]
    assert_equal 150, result[:wake_window_minutes]
    expected = Time.zone.parse("2026-07-08 12:00:00") # 9:30 + 150
    assert_equal expected.iso8601, result[:predicted_at]
  end

  test "predicts bedtime after daily nap count is met" do
    now = Time.zone.parse("2026-07-08 16:00:00")
    nap1 = create_submitted_sleep(
      start_time: Time.zone.parse("2026-07-08 09:30:00"),
      end_time: Time.zone.parse("2026-07-08 10:30:00")
    )
    nap2 = create_submitted_sleep(
      start_time: Time.zone.parse("2026-07-08 13:00:00"),
      end_time: Time.zone.parse("2026-07-08 14:00:00")
    )
    nap3 = create_submitted_sleep(
      start_time: Time.zone.parse("2026-07-08 16:30:00"),
      end_time: Time.zone.parse("2026-07-08 17:30:00")
    )

    result = predict_at(now, submitted_runs: [nap1, nap2, nap3])

    assert_equal "bedtime", result[:status]
    assert_equal 3, result[:naps_today]
    assert_equal 150, result[:wake_window_minutes]
    expected = Time.zone.parse("2026-07-08 20:00:00") # 17:30 + 150
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

  test "with no logged sleep later in the day picks the next remaining nap slot" do
    now = Time.zone.parse("2026-07-08 16:00:00")

    result = predict_at(now, submitted_runs: [])

    assert_equal "next_nap", result[:status]
    assert_equal 150, result[:wake_window_minutes]
    assert_equal Time.zone.parse("2026-07-08 16:30:00").iso8601, result[:predicted_at]
  end

  test "with no logged sleep after day end predicts bedtime at night cutoff" do
    now = Time.zone.parse("2026-07-08 22:30:00")

    result = predict_at(now, submitted_runs: [])

    assert_equal "bedtime", result[:status]
    assert_equal Time.zone.parse("2026-07-08 22:00:00").iso8601, result[:predicted_at]
  end

  test "0-nap preschooler predicts bedtime" do
    @user.update!(
      baby_birthdate: Date.new(2023, 3, 8),
      daily_nap_count: 0
    )
    now = Time.zone.parse("2026-07-08 10:00:00")

    result = predict_at(now, submitted_runs: [])

    assert_equal "bedtime", result[:status]
    assert_equal 0, result[:daily_nap_count]
    assert_equal 0, result[:nap_length_minutes]
    assert_equal Time.zone.parse("2026-07-08 22:00:00").iso8601, result[:predicted_at]
  end

  test "predict_with_range omits range_predictions for exact nap count" do
    result = SleepPredictionService.new(
      @user,
      submitted_runs: [],
      active_run: nil,
      now: Time.zone.parse("2026-07-08 08:00:00")
    ).predict_with_range

    assert_equal 3, result[:daily_nap_count]
    assert_nil result[:daily_nap_count_alt]
    assert_nil result[:range_predictions]
  end

  test "predict_with_range returns both nap count variants" do
    @user.update!(daily_nap_count: 2, daily_nap_count_alt: 3)
    now = Time.zone.parse("2026-07-08 16:00:00")
    nap1 = create_submitted_sleep(
      start_time: Time.zone.parse("2026-07-08 09:30:00"),
      end_time: Time.zone.parse("2026-07-08 10:30:00")
    )
    nap2 = create_submitted_sleep(
      start_time: Time.zone.parse("2026-07-08 12:45:00"),
      end_time: Time.zone.parse("2026-07-08 13:30:00")
    )

    result = SleepPredictionService.new(
      @user,
      submitted_runs: [nap1, nap2],
      active_run: nil,
      now: now
    ).predict_with_range

    assert_equal 2, result[:daily_nap_count]
    assert_equal 3, result[:daily_nap_count_alt]
    assert_equal "bedtime", result[:status]
    assert_equal 2, result[:range_predictions].length

    two_naps = result[:range_predictions][0]
    three_naps = result[:range_predictions][1]

    assert_equal 2, two_naps[:daily_nap_count]
    assert_equal "bedtime", two_naps[:status]
    assert_equal 3, three_naps[:daily_nap_count]
    assert_equal "next_nap", three_naps[:status]
  end

  test "predict_with_range keeps identical active-sleep results for both counts" do
    @user.update!(daily_nap_count: 2, daily_nap_count_alt: 3)
    now = Time.zone.parse("2026-07-08 14:00:00")
    active_run = @user.timer_runs.create!(
      start_time: now - 20.minutes,
      submitted: false,
      active: true,
      run_type: :sleeping
    )

    result = SleepPredictionService.new(
      @user,
      submitted_runs: [],
      active_run: active_run,
      now: now
    ).predict_with_range

    assert_equal "currently_napping", result[:status]
    assert_equal 2, result[:range_predictions].length
    assert_equal ["currently_napping", "currently_napping"],
                 result[:range_predictions].map { |prediction| prediction[:status] }
    assert_equal [2, 3],
                 result[:range_predictions].map { |prediction| prediction[:daily_nap_count] }
    assert_equal [20, 20],
                 result[:range_predictions].map { |prediction| prediction[:active_sleep][:elapsed_minutes] }
  end
end
