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
end
