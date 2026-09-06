# frozen_string_literal: true

class SleepPredictionService
  DEFAULT_DAY_START_MINUTES = User::DEFAULT_DAY_START_MINUTES
  DEFAULT_DAY_END_MINUTES = User::DEFAULT_DAY_END_MINUTES

  STATUSES = %w[
    next_nap
    currently_napping
    currently_sleeping
    bedtime
    needs_birthdate
  ].freeze

  AGE_SCHEDULES = [
    {
      age: 0..1,
      variants: [
        { naps: 4, wake_window_minutes: 50, nap_length_minutes: 70 },
        { naps: 5, wake_window_minutes: 50, nap_length_minutes: 70 },
        { naps: 6, wake_window_minutes: 50, nap_length_minutes: 70 }
      ]
    },
    {
      age: 2..3,
      variants: [
        { naps: 4, wake_window_minutes: 80, nap_length_minutes: 55 },
        { naps: 5, wake_window_minutes: 80, nap_length_minutes: 55 }
      ]
    },
    {
      age: 4..5,
      variants: [
        { naps: 3, wake_window_minutes: 110, nap_length_minutes: 75 },
        { naps: 4, wake_window_minutes: 90, nap_length_minutes: 50 }
      ]
    },
    {
      age: 6..7,
      variants: [
        { naps: 3, wake_window_minutes: 150, nap_length_minutes: 60 }
      ]
    },
    {
      age: 8..10,
      variants: [
        { naps: 2, wake_window_minutes: 180, nap_length_minutes: 90 },
        { naps: 3, wake_window_minutes: 150, nap_length_minutes: 60 }
      ]
    },
    {
      age: 11..13,
      variants: [
        { naps: 2, wake_window_minutes: 210, nap_length_minutes: 90 }
      ]
    },
    {
      age: 14..18,
      variants: [
        { naps: 1, wake_window_minutes: 300, nap_length_minutes: 120 },
        { naps: 2, wake_window_minutes: 240, nap_length_minutes: 75 }
      ]
    },
    {
      age: 19..24,
      variants: [
        { naps: 1, wake_window_minutes: 330, nap_length_minutes: 120 }
      ]
    },
    {
      age: 24..35,
      variants: [
        { naps: 1, wake_window_minutes: 330, nap_length_minutes: 90 },
        { naps: 2, wake_window_minutes: 270, nap_length_minutes: 60 }
      ]
    },
    {
      age: 36..60,
      variants: [
        { naps: 0, wake_window_minutes: 0, nap_length_minutes: 0 },
        { naps: 1, wake_window_minutes: 360, nap_length_minutes: 75 }
      ]
    }
  ].freeze

  def initialize(user, submitted_runs: nil, active_run: :not_provided, now: Time.current)
    @user = user
    @submitted_runs = submitted_runs
    @active_run_param = active_run
    @now = now.in_time_zone
    @today = @now.to_date
  end

  def predict(nap_count: nil)
    resolved_nap_count = normalize_daily_nap_count(nap_count || @user.daily_nap_count)

    return needs_birthdate_result(nap_count: resolved_nap_count) unless @user.baby_birthdate.present?

    schedule = self.class.schedule_for(baby_age_in_months, resolved_nap_count)

    active_sleep = active_sleeping_run
    if active_sleep
      return active_sleep_result(active_sleep, nap_count: resolved_nap_count, schedule: schedule)
    end

    naps_today = naps_completed_today

    if resolved_nap_count.zero? || naps_today >= resolved_nap_count
      return bedtime_result(nap_count: resolved_nap_count, naps_today: naps_today, schedule: schedule)
    end

    if last_wake_time.nil?
      return schedule_from_day_window(
        nap_count: resolved_nap_count,
        naps_today: naps_today,
        schedule: schedule
      )
    end

    wake_minutes = schedule[:wake_window_minutes]
    predicted_at = effective_wake + wake_minutes.minutes

    # Do not schedule another nap at/after the user's day-end cutoff.
    if on_or_after_day_end?(predicted_at)
      return bedtime_result(nap_count: resolved_nap_count, naps_today: naps_today, schedule: schedule)
    end

    build_result(
      status: 'next_nap',
      predicted_at: predicted_at,
      wake_window_minutes: wake_minutes,
      nap_length_minutes: schedule[:nap_length_minutes],
      naps_today: naps_today,
      daily_nap_count: resolved_nap_count
    )
  end

  def predict_with_range
    alt = normalized_daily_nap_count_alt
    primary = predict
    payload = primary.merge(daily_nap_count_alt: alt)
    return payload if alt.nil?

    payload.merge(
      range_predictions: [
        predict(nap_count: primary[:daily_nap_count]),
        predict(nap_count: alt)
      ]
    )
  end

  def self.baby_age_in_months(birthdate, today = Date.current)
    months = ((today.year - birthdate.year) * 12) + (today.month - birthdate.month)
    months -= 1 if today.day < birthdate.day
    [months, 0].max
  end

  def self.schedule_for(age_months, nap_count)
    group = AGE_SCHEDULES.find { |entry| entry[:age].cover?(age_months) } || AGE_SCHEDULES.last
    variants = group[:variants]
    exact = variants.find { |variant| variant[:naps] == nap_count }
    return exact if exact

    variants.min_by { |variant| (variant[:naps] - nap_count).abs }
  end

  def self.night_sleep?(
    timer_run,
    day_start_minutes: DEFAULT_DAY_START_MINUTES,
    day_end_minutes: DEFAULT_DAY_END_MINUTES
  )
    local = timer_run.start_time.in_time_zone
    minutes = (local.hour * 60) + local.min
    minutes < day_start_minutes || minutes >= day_end_minutes
  end

  private

  def baby_age_in_months
    self.class.baby_age_in_months(@user.baby_birthdate, @today)
  end

  def normalize_daily_nap_count(count)
    value = count.to_i
    return 3 if value.negative? || value > 6

    value
  end

  def normalized_daily_nap_count_alt
    alt = @user.daily_nap_count_alt
    return nil if alt.nil?

    lower = normalize_daily_nap_count(@user.daily_nap_count)
    upper = alt.to_i
    return upper if User::ALLOWED_NAP_COUNT_RANGES.include?([lower, upper])

    nil
  end

  def day_start_minutes
    value = @user.day_start_minutes
    return DEFAULT_DAY_START_MINUTES if value.nil?

    value
  end

  def day_end_minutes
    value = @user.day_end_minutes
    return DEFAULT_DAY_END_MINUTES if value.nil?

    value
  end

  def day_start_today
    @now.beginning_of_day + day_start_minutes.minutes
  end

  def day_end_today
    @now.beginning_of_day + day_end_minutes.minutes
  end

  def on_or_after_day_end?(time)
    time.in_time_zone >= day_end_today
  end

  def effective_wake
    wake = last_wake_time
    return day_start_today if wake.nil? || wake < day_start_today

    wake
  end

  def ideal_nap_start_times(nap_count, schedule)
    return [] if nap_count.zero?

    wake_minutes = schedule[:wake_window_minutes]
    nap_length = schedule[:nap_length_minutes]
    times = []
    cursor = day_start_today

    nap_count.times do
      start_time = cursor + wake_minutes.minutes
      break if on_or_after_day_end?(start_time)

      times << start_time
      cursor = start_time + nap_length.minutes
    end

    times
  end

  def schedule_from_day_window(nap_count:, naps_today:, schedule:)
    if @now >= day_end_today
      return bedtime_result(nap_count: nap_count, naps_today: naps_today, schedule: schedule)
    end

    times = ideal_nap_start_times(nap_count, schedule)
    next_time = times.find { |time| time > @now }
    if next_time.nil?
      return bedtime_result(nap_count: nap_count, naps_today: naps_today, schedule: schedule)
    end

    build_result(
      status: 'next_nap',
      predicted_at: next_time,
      wake_window_minutes: schedule[:wake_window_minutes],
      nap_length_minutes: schedule[:nap_length_minutes],
      naps_today: naps_today,
      daily_nap_count: nap_count
    )
  end

  def bedtime_result(nap_count:, naps_today:, schedule:)
    wake_minutes = schedule[:wake_window_minutes]
    predicted_at = if nap_count.zero? || last_wake_time.nil?
                     day_end_today
                   else
                     effective_wake + wake_minutes.minutes
                   end
    predicted_at = day_end_today if predicted_at > day_end_today

    build_result(
      status: 'bedtime',
      predicted_at: predicted_at,
      wake_window_minutes: wake_minutes,
      nap_length_minutes: schedule[:nap_length_minutes],
      naps_today: naps_today,
      daily_nap_count: nap_count
    )
  end

  def sleeping_runs
    @sleeping_runs ||= if @submitted_runs
                         Array(@submitted_runs)
                       else
                         @user.timer_runs
                           .submitted
                           .where(run_type: TimerRun.run_types[:sleeping])
                           .order(end_time: :desc)
                           .to_a
                       end
  end

  def active_sleeping_run
    if @active_run_param != :not_provided
      @active_run_param
    else
      @user.timer_runs.active.where(run_type: TimerRun.run_types[:sleeping]).first
    end
  end

  def naps_completed_today
    sleeping_runs.count do |run|
      next false unless run.start_time && run.end_time

      start_date = run.start_time.in_time_zone.to_date
      end_date = run.end_time.in_time_zone.to_date
      end_date == @today && start_date == @today
    end
  end

  def last_wake_time
    candidates = sleeping_runs
      .select { |run| run.end_time.present? }
      .sort_by { |run| run.end_time }
      .reverse

    ending_today = candidates.find { |run| run.end_time.in_time_zone.to_date == @today }
    wake = ending_today&.end_time || candidates.first&.end_time
    wake&.in_time_zone
  end

  def active_sleep_result(active_sleep, nap_count:, schedule:)
    status = if self.class.night_sleep?(
                active_sleep,
                day_start_minutes: day_start_minutes,
                day_end_minutes: day_end_minutes
              )
               'currently_sleeping'
             else
               'currently_napping'
             end
    elapsed_minutes = ((@now - active_sleep.start_time.in_time_zone) / 60).floor

    build_result(
      status: status,
      predicted_at: nil,
      wake_window_minutes: nil,
      nap_length_minutes: schedule[:nap_length_minutes],
      naps_today: naps_completed_today,
      daily_nap_count: nap_count,
      active_sleep: {
        start_time: active_sleep.start_time.iso8601,
        elapsed_minutes: elapsed_minutes
      }
    )
  end

  def needs_birthdate_result(nap_count:)
    build_result(
      status: 'needs_birthdate',
      predicted_at: nil,
      wake_window_minutes: nil,
      nap_length_minutes: nil,
      naps_today: 0,
      daily_nap_count: nap_count,
      active_sleep: nil
    )
  end

  def build_result(status:, predicted_at:, wake_window_minutes:, nap_length_minutes:, naps_today:, daily_nap_count:, active_sleep: nil)
    {
      status: status,
      predicted_at: predicted_at&.iso8601,
      wake_window_minutes: wake_window_minutes,
      nap_length_minutes: nap_length_minutes,
      naps_today: naps_today,
      daily_nap_count: daily_nap_count,
      active_sleep: active_sleep
    }
  end
end
