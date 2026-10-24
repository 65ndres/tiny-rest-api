# frozen_string_literal: true

# Development-only: fills two weeks of night sleeps, naps, nursing sessions and
# bottle feedings for an existing account so the timeline has something to
# show. Safe to re-run; it replaces that account's timer runs.
#
#   USER_ID=23 bin/rails runner db/seeds/timeline_entries.rb

abort "Development only" unless Rails.env.development?

DAYS = 14

user = User.find(ENV.fetch("USER_ID", 23))
zone = ActiveSupport::TimeZone[user.time_zone.presence || "America/New_York"]
now = Time.current
rng = Random.new(user.id)
jitter = ->(minutes) { rng.rand(-minutes..minutes).minutes }
# Anchor everything to the account's day window so nights start after the day
# ends (otherwise the timeline counts them as naps).
day_start = (user.day_start_minutes || 420).minutes
day_end = (user.day_end_minutes || 1260).minutes

runs = []
feedings = []
DAYS.downto(0) do |days_ago|
  day = zone.now.to_date - days_ago
  midnight = zone.local(day.year, day.month, day.day)

  # A baby either sleeps or feeds, so nothing below overlaps. The night that
  # ends this morning (from just after the day end until just before the day
  # start) is split by a ~2 AM nursing feed.
  night_start = midnight - 1.day + day_end + rng.rand(5..40).minutes
  night_end = midnight + day_start - rng.rand(30..70).minutes
  night_feed_start = midnight + 2.hours + jitter.call(30)
  night_feed_end = night_feed_start + rng.rand(10..25).minutes
  runs << [ night_start, night_feed_start ]
  runs << [ night_feed_end, night_end ]

  # Wake-up feed on the other side, shortly after the night ends.
  wake_feed_start = night_end + rng.rand(5..20).minutes
  first_side, second_side = days_ago.even? ? %i[nursing_left nursing_right] : %i[nursing_right nursing_left]
  feedings << [ first_side, night_feed_start, night_feed_end, {} ]
  feedings << [ second_side, wake_feed_start, wake_feed_start + rng.rand(10..25).minutes, {} ]

  # Midday nap, plus a short late-afternoon catnap on some days.
  nap_start = midnight + day_start + 3.5.hours + jitter.call(45)
  runs << [ nap_start, nap_start + rng.rand(55..120).minutes ]
  if rng.rand < 0.4
    catnap_start = midnight + day_end - 5.hours + jitter.call(30)
    runs << [ catnap_start, catnap_start + rng.rand(20..40).minutes ]
  end

  # Bottles mid-morning, afternoon and before bed.
  [ day_start + 1.hour, day_end - 6.5.hours, day_end - 1.hour ].each do |offset|
    at = midnight + offset + jitter.call(30)
    metadata = { "feeding_type" => [ "Formula", "Breast milk" ].sample(random: rng),
                 "unit" => "oz", "amount" => rng.rand(3..6) }
    feedings << [ :bottle, at, at, metadata ]
  end
end

# A bottle that lands during a sleep moves to just after the baby wakes.
feedings.map! do |run_type, start_time, end_time, metadata|
  next [ run_type, start_time, end_time, metadata ] unless run_type == :bottle

  at = start_time
  while (sleep = runs.find { |sleep_start, sleep_end| at >= sleep_start && at < sleep_end })
    at = sleep[1] + 10.minutes
  end
  [ run_type, at, at, metadata ]
end

entries = runs.map { |start_time, end_time| [ :sleeping, start_time, end_time, {} ] } + feedings

TimerRun.transaction do
  user.timer_runs.destroy_all
  entries.each do |run_type, start_time, end_time, metadata|
    start_time = start_time.change(sec: 0)
    end_time = end_time.change(sec: 0)
    # Skip entries that haven't finished yet; only completed runs are listed.
    next if end_time > now

    run = user.timer_runs.create!(
      start_time: start_time,
      end_time: end_time,
      duration: ((end_time - start_time) * 1000).to_i,
      submitted: true,
      run_type: run_type,
      metadata: metadata
    )
    # Creating a run marks it as the running timer; these are finished.
    run.update_columns(active: false)
  end
end

counts = user.timer_runs.group(:run_type).count
puts "User #{user.id} (#{user.email}) over the last #{DAYS + 1} days: #{counts}"
