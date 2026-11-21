# frozen_string_literal: true

require "test_helper"

class BabyTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(
      email: "baby_model@example.com",
      password: "password123",
      password_confirmation: "password123",
      baby_name: "Ana",
      baby_birthdate: 6.months.ago.to_date,
      daily_nap_count: 2
    )
  end

  test "new users get a first baby built from the legacy baby attributes" do
    assert_equal 1, @user.babies.count
    baby = @user.babies.first
    assert_equal "Ana", baby.name
    assert_equal 6.months.ago.to_date, baby.birthdate
    assert_equal 2, baby.daily_nap_count
  end

  test "users created without baby attributes still get a default baby" do
    user = User.create!(email: "no_baby@example.com", password: "password123")

    assert_equal 1, user.babies.count
    assert_equal 3, user.babies.first.daily_nap_count
    assert_equal "Baby", user.babies.first.display_name
  end

  test "legacy user setters update the first baby" do
    @user.update!(baby_birthdate: 3.months.ago.to_date, daily_nap_count: 4)

    assert_equal 3.months.ago.to_date, @user.babies.first.reload.birthdate
    assert_equal 4, @user.babies.first.daily_nap_count
  end

  test "validates the nap count range and birthdate window" do
    baby = @user.babies.build(name: "Bo", daily_nap_count: 2, daily_nap_count_alt: 4)
    refute baby.valid?
    assert_includes baby.errors[:daily_nap_count_alt], "must be an allowed nap range"

    baby = @user.babies.build(name: "Bo", birthdate: Date.current + 1.day)
    refute baby.valid?
    assert_includes baby.errors[:birthdate], "must be in the past"
  end

  test "validates name length and strips blanks" do
    baby = @user.babies.create!(name: "  Bo  ")
    assert_equal "Bo", baby.name

    baby.name = "x" * (Baby::MAX_NAME_LENGTH + 1)
    refute baby.valid?
  end

  test "cannot destroy the last baby" do
    baby = @user.babies.first

    refute baby.destroy
    assert Baby.exists?(baby.id)
  end

  test "destroying a baby removes its timer runs only" do
    first = @user.babies.first
    second = @user.babies.create!(name: "Bo")
    first.timer_runs.create!(user: @user, start_time: 2.hours.ago, end_time: 1.hour.ago,
                             duration: 3_600_000, submitted: true)
    kept = @user.timer_runs.create!(baby: second, start_time: 4.hours.ago, end_time: 3.hours.ago,
                                    duration: 3_600_000, submitted: true)

    assert first.destroy
    assert_equal [ kept.id ], @user.timer_runs.pluck(:id)
  end

  test "timer runs created through the user land on the first baby" do
    run = @user.timer_runs.create!(start_time: 1.hour.ago)

    assert_equal @user.babies.first.id, run.baby_id
  end

  test "timer runs cannot be attached to another account's baby" do
    other = User.create!(email: "other_baby@example.com", password: "password123")
    run = @user.timer_runs.build(baby: other.primary_baby, start_time: 1.hour.ago)

    refute run.valid?
    assert run.errors[:baby].present?
  end

  test "overlap validation is per baby" do
    second = @user.babies.create!(name: "Bo")
    @user.timer_runs.create!(start_time: 2.hours.ago, end_time: 1.hour.ago,
                             duration: 3_600_000, submitted: true)

    twin_nap = @user.timer_runs.build(baby: second, start_time: 2.hours.ago, end_time: 1.hour.ago,
                                      duration: 3_600_000, submitted: true)
    assert twin_nap.valid?, twin_nap.errors.full_messages.to_sentence

    same_baby = @user.timer_runs.build(start_time: 90.minutes.ago, end_time: 30.minutes.ago,
                                       duration: 3_600_000, submitted: true)
    refute same_baby.valid?
  end
end
