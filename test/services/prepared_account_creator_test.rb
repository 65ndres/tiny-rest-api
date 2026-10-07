# frozen_string_literal: true

require "test_helper"

class PreparedAccountCreatorTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::TimeHelpers

  setup do
    @zone = Time.find_zone!("America/New_York")
  end

  test "creates a verified pro account with today's naps already taken" do
    travel_to @zone.parse("2026-10-06 15:00:00") do
      result = nil

      assert_difference -> { User.count }, 1 do
        result = PreparedAccountCreator.call(daily_nap_count: 3, naps_taken: 1)
      end

      user = result.user.reload
      assert_equal "password123", result.password
      assert user.valid_password?(result.password)
      assert user.email_verified_at.present?
      assert_equal 3, user.daily_nap_count
      assert_equal "Sam", user.baby_name
      assert user.baby_birthdate.present?

      onboarding = user.onboarding
      assert onboarding.completed_at.present?
      assert_equal "paywall", onboarding.last_completed_step
      assert_equal "pro", user.subscription_type_for_payload
      assert_equal true, user.jwt_payload[:onboarding_completed]

      naps = user.timer_runs.submitted.where(run_type: "sleeping")
      assert_equal 1, naps.count
      assert_equal 0, user.timer_runs.where(active: true).count
      nap = naps.first
      assert nap.end_time > nap.start_time
      assert_equal nap.end_time.to_date, @zone.parse("2026-10-06 15:00:00").to_date
      assert_equal nap.start_time.in_time_zone(@zone).to_date, nap.end_time.in_time_zone(@zone).to_date

      prediction = SleepPredictionService.new(user, now: Time.current).predict
      assert_equal 3, prediction[:daily_nap_count]
      assert_equal 1, prediction[:naps_today]
      assert_not_equal "currently_napping", prediction[:status]
    end
  end

  test "allows zero naps already taken" do
    travel_to @zone.parse("2026-10-06 15:00:00") do
      result = PreparedAccountCreator.call(daily_nap_count: 2, naps_taken: 0)

      assert_equal 0, result.user.timer_runs.count
      assert_equal "pro", result.user.subscription_type_for_payload
      assert result.user.onboarding.completed_at.present?
    end
  end

  test "rejects nap counts outside the allowed range" do
    assert_no_difference -> { User.count } do
      error = assert_raises(PreparedAccountCreator::Error) do
        PreparedAccountCreator.call(daily_nap_count: 7, naps_taken: 0)
      end
      assert_match(/between 0 and 6/, error.message)
    end
  end

  test "rejects a non-numeric nap count" do
    error = assert_raises(PreparedAccountCreator::Error) do
      PreparedAccountCreator.call(daily_nap_count: "three", naps_taken: 1)
    end

    assert_match(/whole number/, error.message)
  end
end
