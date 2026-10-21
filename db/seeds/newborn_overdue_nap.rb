# frozen_string_literal: true

# Development-only test account: a 20-day-old newborn whose next nap is
# 10 minutes overdue right now. Safe to re-run; it resets the account's sleeps.
#
#   bin/rails runner db/seeds/newborn_overdue_nap.rb

abort "Development only" unless Rails.env.development?

EMAIL = "newborn.test@tinyrest.test"
PASSWORD = "newborn-dev-pass"
TIME_ZONE = "America/New_York"

user = User.find_or_initialize_by(email: EMAIL)
user.assign_attributes(
  password: PASSWORD,
  password_confirmation: PASSWORD,
  username: "newborntest",
  first_name: "Newborn",
  last_name: "Test",
  baby_name: "Baby",
  email_verified_at: user.email_verified_at || Time.current,
  time_zone: TIME_ZONE,
  baby_birthdate: Time.current.in_time_zone(TIME_ZONE).to_date - 20.days,
  daily_nap_count: 5,
  daily_nap_count_alt: nil,
  day_start_minutes: 420, # 7:00 AM wake-up
  day_end_minutes: 1320   # 10:00 PM
)
user.save!

onboarding = user.onboarding || user.build_onboarding
onboarding.update!(last_completed_step: "paywall", completed_at: onboarding.completed_at || Time.current)

# Newborn wake window is 50 min, so a nap that ended 60 min ago makes the next
# one due 10 min ago.
now = Time.current.change(sec: 0)
wake_today = now.in_time_zone(TIME_ZONE).beginning_of_day + 7.hours
last_nap_end = now - 60.minutes
last_nap_start = last_nap_end - 70.minutes

user.timer_runs.destroy_all
[
  [ wake_today - 11.hours, wake_today ],
  [ last_nap_start, last_nap_end ]
].each do |start_time, end_time|
  run = user.timer_runs.create!(
    start_time: start_time,
    end_time: end_time,
    duration: ((end_time - start_time) * 1000).to_i,
    submitted: true,
    run_type: :sleeping
  )
  # Creating a run marks it as the running timer; these are finished sleeps.
  run.update_columns(active: false)
end

prediction = SleepPredictionService.new(user).predict
puts "#{EMAIL}: #{prediction[:status]} at #{Time.zone.parse(prediction[:predicted_at]).in_time_zone(TIME_ZONE).strftime('%-I:%M %p')} (now #{now.in_time_zone(TIME_ZONE).strftime('%-I:%M %p')})"
