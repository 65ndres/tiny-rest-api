# frozen_string_literal: true

require "test_helper"

class TimerRunTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(
      email: "timerrun@example.com",
      password: "password123",
      password_confirmation: "password123",
      username: "timerrunuser",
      first_name: "Timer",
      last_name: "Run"
    )
  end

  test "allows end_time without submitted when duration is absent" do
    timer_run = @user.timer_runs.build(
      start_time: 1.hour.ago,
      end_time: Time.current,
      submitted: false,
      active: false
    )

    assert timer_run.valid?
  end

  test "sleeping run is invalid when end_time is before start_time" do
    start_time = Time.zone.parse("2026-06-01 12:00:00")
    timer_run = @user.timer_runs.build(
      start_time: start_time,
      end_time: start_time - 1.minute,
      duration: 60_000,
      submitted: true,
      run_type: :sleeping
    )

    assert_not timer_run.valid?
    assert_includes timer_run.errors[:end_time], "must be after start time"
  end

  test "sleeping run is invalid when end_time equals start_time" do
    start_time = Time.zone.parse("2026-06-01 12:00:00")
    timer_run = @user.timer_runs.build(
      start_time: start_time,
      end_time: start_time,
      duration: 0,
      submitted: true,
      run_type: :sleeping
    )

    assert_not timer_run.valid?
    assert_includes timer_run.errors[:end_time], "must be after start time"
  end

  test "nursing run is invalid when end_time is before start_time" do
    start_time = Time.zone.parse("2026-06-01 12:00:00")
    timer_run = @user.timer_runs.build(
      start_time: start_time,
      end_time: start_time - 5.minutes,
      duration: 300_000,
      submitted: true,
      run_type: :nursing_left
    )

    assert_not timer_run.valid?
    assert_includes timer_run.errors[:end_time], "must be after start time"
  end

  test "sleeping run is valid when end_time is after start_time" do
    start_time = Time.zone.parse("2026-06-01 12:00:00")
    timer_run = @user.timer_runs.build(
      start_time: start_time,
      end_time: start_time + 30.minutes,
      duration: 1_800_000,
      submitted: true,
      run_type: :sleeping
    )

    assert timer_run.valid?
  end

  test "bottle run allows end_time equal to start_time" do
    start_time = Time.zone.parse("2026-06-01 12:00:00")
    timer_run = @user.timer_runs.build(
      start_time: start_time,
      end_time: start_time,
      duration: 0,
      submitted: true,
      run_type: :bottle,
      active: false
    )

    assert timer_run.valid?
  end

  test "bottle run is invalid when end_time is before start_time" do
    start_time = Time.zone.parse("2026-06-01 12:00:00")
    timer_run = @user.timer_runs.build(
      start_time: start_time,
      end_time: start_time - 1.minute,
      duration: 0,
      submitted: true,
      run_type: :bottle,
      active: false
    )

    assert_not timer_run.valid?
    assert_includes timer_run.errors[:end_time], "must be after start time"
  end

  test "sleeping run is invalid when start_time is in the future" do
    start_time = 1.hour.from_now
    timer_run = @user.timer_runs.build(
      start_time: start_time,
      end_time: start_time + 30.minutes,
      duration: 1_800_000,
      submitted: true,
      run_type: :sleeping
    )

    assert_not timer_run.valid?
    assert_includes timer_run.errors[:start_time], "cannot be in the future"
  end

  test "nursing run is invalid when start_time is in the future" do
    start_time = 1.hour.from_now
    timer_run = @user.timer_runs.build(
      start_time: start_time,
      end_time: start_time + 10.minutes,
      duration: 600_000,
      submitted: true,
      run_type: :nursing_left
    )

    assert_not timer_run.valid?
    assert_includes timer_run.errors[:start_time], "cannot be in the future"
  end

  test "bottle run is invalid when start_time is in the future" do
    start_time = 1.hour.from_now
    timer_run = @user.timer_runs.build(
      start_time: start_time,
      end_time: start_time,
      duration: 0,
      submitted: true,
      run_type: :bottle,
      active: false
    )

    assert_not timer_run.valid?
    assert_includes timer_run.errors[:start_time], "cannot be in the future"
  end

  test "allows start_time within one minute skew of now" do
    start_time = 30.seconds.from_now
    timer_run = @user.timer_runs.build(
      start_time: start_time,
      submitted: false,
      active: true,
      run_type: :sleeping
    )

    assert timer_run.valid?
  end

  test "allows start_time in the past" do
    timer_run = @user.timer_runs.build(
      start_time: 1.hour.ago,
      submitted: false,
      active: true,
      run_type: :sleeping
    )

    assert timer_run.valid?
  end

  def finished_run(start_time, end_time, run_type: :sleeping, user: @user)
    user.timer_runs.build(
      start_time: start_time,
      end_time: end_time,
      duration: ((end_time - start_time) * 1000).to_i,
      submitted: true,
      run_type: run_type
    )
  end

  test "finished run cannot overlap another finished run" do
    @user.update!(time_zone: "America/New_York")
    sleep_start = Time.zone.parse("2026-06-01 16:00:00") # 12:00 PM New York
    finished_run(sleep_start, sleep_start + 2.hours).save!

    nursing = finished_run(sleep_start + 1.hour, sleep_start + 3.hours, run_type: :nursing_left)

    assert_not nursing.valid?
    assert_includes nursing.errors[:base],
      "This overlaps a sleep from Jun 1, 12:00 PM to 2:00 PM. A baby can only sleep or feed at one time."
  end

  test "bottle feeding inside a sleep is an overlap" do
    sleep_start = 3.hours.ago
    finished_run(sleep_start, sleep_start + 2.hours).save!

    at = sleep_start + 30.minutes
    bottle = finished_run(at, at, run_type: :bottle)

    assert_not bottle.valid?
    assert_match(/overlaps a sleep/, bottle.errors[:base].first)
  end

  test "sleep cannot be logged over an existing bottle feeding" do
    at = 2.hours.ago
    finished_run(at, at, run_type: :bottle).save!

    sleep = finished_run(at - 30.minutes, at + 30.minutes)

    assert_not sleep.valid?
    assert_match(/overlaps a bottle feeding at/, sleep.errors[:base].first)
  end

  test "runs that only touch at the edges are allowed" do
    sleep_start = 4.hours.ago
    finished_run(sleep_start, sleep_start + 1.hour).save!

    assert finished_run(sleep_start + 1.hour, sleep_start + 90.minutes, run_type: :nursing_right).valid?
    assert finished_run(sleep_start + 1.hour, sleep_start + 1.hour, run_type: :bottle).valid?
  end

  test "editing a run does not conflict with itself" do
    sleep_start = 4.hours.ago
    run = finished_run(sleep_start, sleep_start + 1.hour)
    run.save!

    run.end_time = sleep_start + 2.hours
    assert run.valid?
  end

  test "other users runs and unfinished runs do not count as overlaps" do
    other = User.create!(
      email: "timerrun2@example.com",
      password: "password123",
      password_confirmation: "password123",
      username: "timerrunuser2",
      first_name: "Other",
      last_name: "User"
    )
    sleep_start = 4.hours.ago
    finished_run(sleep_start, sleep_start + 2.hours, user: other).save!
    @user.timer_runs.create!(start_time: sleep_start, submitted: false, active: true)

    assert finished_run(sleep_start + 30.minutes, sleep_start + 1.hour).valid?
  end
end
