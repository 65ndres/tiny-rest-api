# frozen_string_literal: true

require 'test_helper'

class TimerRunTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(
      email: 'timerrun@example.com',
      password: 'password123',
      password_confirmation: 'password123',
      username: 'timerrunuser',
      first_name: 'Timer',
      last_name: 'Run'
    )
  end

  test 'allows end_time without submitted when duration is absent' do
    timer_run = @user.timer_runs.build(
      start_time: 1.hour.ago,
      end_time: Time.current,
      submitted: false,
      active: false
    )

    assert timer_run.valid?
  end

  test 'sleeping run is invalid when end_time is before start_time' do
    start_time = Time.zone.parse('2026-06-01 12:00:00')
    timer_run = @user.timer_runs.build(
      start_time: start_time,
      end_time: start_time - 1.minute,
      duration: 60_000,
      submitted: true,
      run_type: :sleeping
    )

    assert_not timer_run.valid?
    assert_includes timer_run.errors[:end_time], 'must be after start time'
  end

  test 'sleeping run is invalid when end_time equals start_time' do
    start_time = Time.zone.parse('2026-06-01 12:00:00')
    timer_run = @user.timer_runs.build(
      start_time: start_time,
      end_time: start_time,
      duration: 0,
      submitted: true,
      run_type: :sleeping
    )

    assert_not timer_run.valid?
    assert_includes timer_run.errors[:end_time], 'must be after start time'
  end

  test 'nursing run is invalid when end_time is before start_time' do
    start_time = Time.zone.parse('2026-06-01 12:00:00')
    timer_run = @user.timer_runs.build(
      start_time: start_time,
      end_time: start_time - 5.minutes,
      duration: 300_000,
      submitted: true,
      run_type: :nursing_left
    )

    assert_not timer_run.valid?
    assert_includes timer_run.errors[:end_time], 'must be after start time'
  end

  test 'sleeping run is valid when end_time is after start_time' do
    start_time = Time.zone.parse('2026-06-01 12:00:00')
    timer_run = @user.timer_runs.build(
      start_time: start_time,
      end_time: start_time + 30.minutes,
      duration: 1_800_000,
      submitted: true,
      run_type: :sleeping
    )

    assert timer_run.valid?
  end

  test 'bottle run allows end_time equal to start_time' do
    start_time = Time.zone.parse('2026-06-01 12:00:00')
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

  test 'bottle run is invalid when end_time is before start_time' do
    start_time = Time.zone.parse('2026-06-01 12:00:00')
    timer_run = @user.timer_runs.build(
      start_time: start_time,
      end_time: start_time - 1.minute,
      duration: 0,
      submitted: true,
      run_type: :bottle,
      active: false
    )

    assert_not timer_run.valid?
    assert_includes timer_run.errors[:end_time], 'must be after start time'
  end

  test 'sleeping run is invalid when start_time is in the future' do
    start_time = 1.hour.from_now
    timer_run = @user.timer_runs.build(
      start_time: start_time,
      end_time: start_time + 30.minutes,
      duration: 1_800_000,
      submitted: true,
      run_type: :sleeping
    )

    assert_not timer_run.valid?
    assert_includes timer_run.errors[:start_time], 'cannot be in the future'
  end

  test 'nursing run is invalid when start_time is in the future' do
    start_time = 1.hour.from_now
    timer_run = @user.timer_runs.build(
      start_time: start_time,
      end_time: start_time + 10.minutes,
      duration: 600_000,
      submitted: true,
      run_type: :nursing_left
    )

    assert_not timer_run.valid?
    assert_includes timer_run.errors[:start_time], 'cannot be in the future'
  end

  test 'bottle run is invalid when start_time is in the future' do
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
    assert_includes timer_run.errors[:start_time], 'cannot be in the future'
  end

  test 'allows start_time within one minute skew of now' do
    start_time = 30.seconds.from_now
    timer_run = @user.timer_runs.build(
      start_time: start_time,
      submitted: false,
      active: true,
      run_type: :sleeping
    )

    assert timer_run.valid?
  end

  test 'allows start_time in the past' do
    timer_run = @user.timer_runs.build(
      start_time: 1.hour.ago,
      submitted: false,
      active: true,
      run_type: :sleeping
    )

    assert timer_run.valid?
  end
end
