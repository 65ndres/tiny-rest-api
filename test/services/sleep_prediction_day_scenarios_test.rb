# frozen_string_literal: true

require "test_helper"

# Walks through a full day for each age group: the baby wakes at 7:00 AM,
# takes every predicted nap on time, and we check the prediction just before
# each nap is due (with all earlier naps already logged).
class SleepPredictionDayScenariosTest < ActiveSupport::TestCase
  TODAY = Date.new(2026, 10, 20)
  WAKE_MINUTES = 420      # 7:00 AM
  DAY_END_MINUTES = 1320  # 10:00 PM
  CHECK_BEFORE_NAP_MINUTES = 10

  setup do
    @user = User.create!(
      email: "day_scenarios@example.com",
      password: "password123",
      password_confirmation: "password123",
      username: "dayscenariosuser",
      first_name: "Day",
      last_name: "Parent",
      baby_birthdate: TODAY - 20.days,
      daily_nap_count: 5,
      day_start_minutes: WAKE_MINUTES,
      day_end_minutes: DAY_END_MINUTES
    )
  end

  def at(clock)
    Time.zone.parse("#{TODAY} #{clock}")
  end

  def night_sleep
    TimerRun.new(
      start_time: at("07:00") - 11.hours,
      end_time: at("07:00"),
      submitted: true,
      active: false,
      run_type: :sleeping
    )
  end

  def nap(start_time, length_minutes)
    TimerRun.new(
      start_time: start_time,
      end_time: start_time + length_minutes.minutes,
      submitted: true,
      active: false,
      run_type: :sleeping
    )
  end

  def predict_at(now, runs)
    SleepPredictionService.new(
      @user,
      submitted_runs: runs.sort_by(&:end_time).reverse,
      active_run: nil,
      now: now
    ).predict
  end

  # 20-day-old newborn, 5 naps, 7:00 AM wake: 50 min wake window, 70 min naps,
  # so naps fall at 7:50, 9:50, 11:50, 1:50 and 3:50.
  test "20-day-old newborn predictions through the day" do
    expected = [
      [ "07:40", 0, "next_nap", "07:50" ],
      [ "09:40", 1, "next_nap", "09:50" ],
      [ "11:40", 2, "next_nap", "11:50" ],
      [ "13:40", 3, "next_nap", "13:50" ],
      [ "15:40", 4, "next_nap", "15:50" ],
      [ "17:40", 5, "bedtime", "17:50" ]
    ]

    expected.each do |clock, naps_before, status, predicted|
      runs = [ night_sleep ]
      naps_before.times do |index|
        runs << nap(at("07:50") + (index * 120).minutes, 70)
      end

      result = predict_at(at(clock), runs)

      assert_equal 0, SleepPredictionService.baby_age_in_months(@user.baby_birthdate, TODAY)
      assert_equal status, result[:status], "status at #{clock}"
      assert_equal naps_before, result[:naps_today], "naps_today at #{clock}"
      assert_equal 50, result[:wake_window_minutes], "wake window at #{clock}"
      assert_equal at(predicted).iso8601, result[:predicted_at], "prediction at #{clock}"
    end
  end

  # Same newborn, but only the 7:00 AM wake-up is logged and no naps are
  # taken. Missed naps move forward to the next slot on the 2-hour cycle.
  test "20-day-old newborn with no naps taken moves to the next open slot" do
    expected = [
      [ "07:40", "next_nap", "07:50" ],
      [ "09:40", "next_nap", "09:50" ],
      [ "11:40", "next_nap", "11:50" ],
      [ "13:40", "next_nap", "13:50" ],
      [ "15:40", "next_nap", "15:50" ],
      [ "17:40", "bedtime", "22:00" ]
    ]

    expected.each do |clock, status, predicted|
      result = predict_at(at(clock), [ night_sleep ])

      assert_equal status, result[:status], "status at #{clock}"
      assert_equal 0, result[:naps_today], "naps_today at #{clock}"
      assert_equal at(predicted).iso8601, result[:predicted_at], "prediction at #{clock}"
    end
  end

  test "20-day-old newborn with nothing logged follows the day schedule" do
    expected = [
      [ "07:40", "next_nap", "07:50" ],
      [ "09:40", "next_nap", "09:50" ],
      [ "11:40", "next_nap", "11:50" ],
      [ "13:40", "next_nap", "13:50" ],
      [ "15:40", "next_nap", "15:50" ],
      [ "17:40", "bedtime", "22:00" ]
    ]

    expected.each do |clock, status, predicted|
      result = predict_at(at(clock), [])

      assert_equal status, result[:status], "status at #{clock}"
      assert_equal at(predicted).iso8601, result[:predicted_at], "prediction at #{clock}"
    end
  end

  test "a missed nap after earlier naps moves forward and uses up a nap" do
    # Two naps taken, then the 11:50 nap is skipped.
    runs = [ night_sleep, nap(at("07:50"), 70), nap(at("09:50"), 70) ]

    at_noon_forty = predict_at(at("12:40"), runs)
    assert_equal "next_nap", at_noon_forty[:status]
    assert_equal 2, at_noon_forty[:naps_today]
    assert_equal at("13:50").iso8601, at_noon_forty[:predicted_at]

    # 5 naps a day with 2 taken leaves 3 slots: 11:50, 1:50, 3:50.
    after_last_slot = predict_at(at("16:11"), runs)
    assert_equal "bedtime", after_last_slot[:status]
    assert_equal at("22:00").iso8601, after_last_slot[:predicted_at]
  end

  test "an unstarted nap stays the prediction for a 20 minute grace period" do
    [ [ "08:00", "07:50" ], [ "08:10", "07:50" ], [ "08:11", "09:50" ] ].each do |clock, predicted|
      with_wake_logged = predict_at(at(clock), [ night_sleep ])
      assert_equal "next_nap", with_wake_logged[:status], "status at #{clock}"
      assert_equal at(predicted).iso8601, with_wake_logged[:predicted_at], "wake logged at #{clock}"

      nothing_logged = predict_at(at(clock), [])
      assert_equal at(predicted).iso8601, nothing_logged[:predicted_at], "nothing logged at #{clock}"
    end
  end

  test "the last nap slot of the day also gets the grace period" do
    still_overdue = predict_at(at("16:10"), [ night_sleep ])
    assert_equal "next_nap", still_overdue[:status]
    assert_equal at("15:50").iso8601, still_overdue[:predicted_at]

    missed = predict_at(at("16:11"), [ night_sleep ])
    assert_equal "bedtime", missed[:status]
    assert_equal at("22:00").iso8601, missed[:predicted_at]
  end

  test "a prediction still ahead is not moved" do
    ahead = predict_at(at("07:49"), [ night_sleep ])
    assert_equal at("07:50").iso8601, ahead[:predicted_at]

    due_now = predict_at(at("07:50"), [ night_sleep ])
    assert_equal at("07:50").iso8601, due_now[:predicted_at]
  end

  test "20-day-old newborn on 6 naps still has a nap due at 5:50 PM" do
    @user.update!(daily_nap_count: 6)
    runs = [ night_sleep ] + 5.times.map { |index| nap(at("07:50") + (index * 120).minutes, 70) }

    result = predict_at(at("17:40"), runs)

    assert_equal "next_nap", result[:status]
    assert_equal 5, result[:naps_today]
    assert_equal at("17:50").iso8601, result[:predicted_at]
  end

  # One representative age (in months) per age group, with each nap-count
  # variant that group supports.
  AGE_GROUP_CASES = SleepPredictionService::AGE_SCHEDULES.flat_map do |group|
    group[:variants].map { |variant| [ group[:age], group[:age].first, variant ] }
  end.freeze

  AGE_GROUP_CASES.each do |age_range, age_months, variant|
    test "full day for #{age_range} months on #{variant[:naps]} naps" do
      @user.update!(
        baby_birthdate: TODAY << age_months,
        daily_nap_count: variant[:naps]
      )
      assert_equal age_months, SleepPredictionService.baby_age_in_months(@user.baby_birthdate, TODAY)

      wake_window = if variant[:wake_window_minutes] == SleepPredictionService::FULL_DAY_WAKE_WINDOW
                      DAY_END_MINUTES - WAKE_MINUTES
      else
                      variant[:wake_window_minutes]
      end
      day_end = at("22:00")

      runs = [ night_sleep ]
      last_wake = at("07:00")

      variant[:naps].times do |index|
        nap_start = last_wake + wake_window.minutes
        break if nap_start >= day_end

        check = nap_start - CHECK_BEFORE_NAP_MINUTES.minutes
        result = predict_at(check, runs)

        assert_equal "next_nap", result[:status], "nap #{index + 1} status at #{check.strftime('%H:%M')}"
        assert_equal index, result[:naps_today], "naps before nap #{index + 1}"
        assert_equal wake_window, result[:wake_window_minutes]
        assert_equal variant[:nap_length_minutes], result[:nap_length_minutes]
        assert_equal nap_start.iso8601, result[:predicted_at], "nap #{index + 1} time"

        runs << nap(nap_start, variant[:nap_length_minutes])
        last_wake = runs.last.end_time
      end

      expected_bedtime = [ last_wake + wake_window.minutes, day_end ].min
      check = [ expected_bedtime, day_end ].min - CHECK_BEFORE_NAP_MINUTES.minutes
      result = predict_at(check, runs)

      assert_equal "bedtime", result[:status], "bedtime status at #{check.strftime('%H:%M')}"
      assert_equal expected_bedtime.iso8601, result[:predicted_at], "bedtime time"
    end
  end
end
