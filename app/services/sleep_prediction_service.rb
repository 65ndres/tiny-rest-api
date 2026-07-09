# frozen_string_literal: true

class SleepPredictionService
  NIGHT_START_HOUR = 19
  NIGHT_END_HOUR = 6

  STATUSES = %w[
    next_nap
    currently_napping
    currently_sleeping
    bedtime
    needs_birthdate
  ].freeze

  def initialize(user, submitted_runs: nil, active_run: :not_provided, now: Time.current)
    @user = user
    @submitted_runs = submitted_runs
    @active_run_param = active_run
    @now = now.in_time_zone
    @today = @now.to_date
  end

  def predict
    return needs_birthdate_result unless @user.baby_birthdate.present?

    active_sleep = active_sleeping_run
    if active_sleep
      return active_sleep_result(active_sleep)
    end

    nap_count = normalize_daily_nap_count(@user.daily_nap_count)
    naps_today = naps_completed_today
    base_minutes = base_wake_window_minutes(baby_age_in_months)

    if naps_today >= nap_count
      slot_index = nap_count
      wake_minutes = wake_window_for_slot(slot_index, nap_count, base_minutes)
      predicted_at = last_wake_time + wake_minutes.minutes

      return build_result(
        status: 'bedtime',
        predicted_at: predicted_at,
        wake_window_minutes: wake_minutes,
        naps_today: naps_today,
        daily_nap_count: nap_count
      )
    end

    slot_index = naps_today
    wake_minutes = wake_window_for_slot(slot_index, nap_count, base_minutes)
    anchor = last_wake_time || @now
    predicted_at = anchor + wake_minutes.minutes

    build_result(
      status: 'next_nap',
      predicted_at: predicted_at,
      wake_window_minutes: wake_minutes,
      naps_today: naps_today,
      daily_nap_count: nap_count
    )
  end

  def self.baby_age_in_months(birthdate, today = Date.current)
    months = ((today.year - birthdate.year) * 12) + (today.month - birthdate.month)
    months -= 1 if today.day < birthdate.day
    [months, 0].max
  end

  def self.base_wake_window_minutes(age_months)
    age_days = nil # only used when birthdate passed for weeks calc - handled via age_months==0

    case age_months
    when 0
      48
    when 1..2
      75
    when 3..4
      98
    when 5..7
      150
    when 8..10
      180
    when 11..14
      210
    when 15..24
      300
    else
      330
    end
  end

  def self.slot_multipliers(daily_nap_count)
    if daily_nap_count == 1
      [1.2, 0.85]
    else
      slots = daily_nap_count + 1
      multipliers = Array.new(slots, 1.0)
      multipliers[0] = 0.85
      multipliers[-1] = 1.2
      multipliers
    end
  end

  def self.wake_window_for_slot(slot_index, daily_nap_count, base_minutes)
    multipliers = slot_multipliers(daily_nap_count)
    index = [[slot_index, 0].max, multipliers.length - 1].min
    (base_minutes * multipliers[index]).round
  end

  def self.night_sleep?(timer_run, now = Time.current)
    hour = timer_run.start_time.in_time_zone.hour
    hour >= NIGHT_START_HOUR || hour < NIGHT_END_HOUR
  end

  private

  def baby_age_in_months
    self.class.baby_age_in_months(@user.baby_birthdate, @today)
  end

  def base_wake_window_minutes(age_months)
    self.class.base_wake_window_minutes(age_months)
  end

  def wake_window_for_slot(slot_index, daily_nap_count, base_minutes)
    self.class.wake_window_for_slot(slot_index, daily_nap_count, base_minutes)
  end

  def normalize_daily_nap_count(count)
    value = count.to_i
    return 3 if value < 1 || value > 5

    value
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

  def active_sleep_result(active_sleep)
    status = self.class.night_sleep?(active_sleep, @now) ? 'currently_sleeping' : 'currently_napping'
    elapsed_minutes = ((@now - active_sleep.start_time.in_time_zone) / 60).floor

    build_result(
      status: status,
      predicted_at: nil,
      wake_window_minutes: nil,
      naps_today: naps_completed_today,
      daily_nap_count: normalize_daily_nap_count(@user.daily_nap_count),
      active_sleep: {
        start_time: active_sleep.start_time.iso8601,
        elapsed_minutes: elapsed_minutes
      }
    )
  end

  def needs_birthdate_result
    build_result(
      status: 'needs_birthdate',
      predicted_at: nil,
      wake_window_minutes: nil,
      naps_today: 0,
      daily_nap_count: normalize_daily_nap_count(@user.daily_nap_count),
      active_sleep: nil
    )
  end

  def build_result(status:, predicted_at:, wake_window_minutes:, naps_today:, daily_nap_count:, active_sleep: nil)
    {
      status: status,
      predicted_at: predicted_at&.iso8601,
      wake_window_minutes: wake_window_minutes,
      naps_today: naps_today,
      daily_nap_count: daily_nap_count,
      active_sleep: active_sleep
    }
  end
end
