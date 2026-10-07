# frozen_string_literal: true

# Builds a verified account that can log in immediately, with onboarding
# finished on the Pro plan and today's naps already recorded.
class PreparedAccountCreator
  class Error < StandardError; end

  PASSWORD = "password123"
  TIME_ZONE = "America/New_York"
  BABY_NAME = "Sam"
  MAX_DAILY_NAPS = 6
  MAX_NAPS_TAKEN = 12
  PREFERRED_NAP_LENGTH = 45.minutes
  PREFERRED_GAP = 30.minutes

  # Months of age whose sleep schedule includes this exact nap count.
  BIRTHDATE_MONTHS_AGO = {
    0 => 36,
    1 => 19,
    2 => 11,
    3 => 6,
    4 => 4,
    5 => 2,
    6 => 1
  }.freeze

  Result = Struct.new(
    :user,
    :email,
    :password,
    :daily_nap_count,
    :naps_taken,
    keyword_init: true
  )

  def self.call(...)
    new(...).call
  end

  def initialize(daily_nap_count:, naps_taken:, email: nil, password: PASSWORD, time_zone: TIME_ZONE)
    @daily_nap_count = integer_param(daily_nap_count, "Number of naps")
    @naps_taken = integer_param(naps_taken, "Number of naps already taken")
    @email = email.presence || generated_email
    @password = password
    @time_zone = time_zone
  end

  def call
    validate!

    user = User.transaction do
      created = User.create!(user_attributes)
      created.onboarding.update!(
        completed_at: Time.current,
        last_completed_step: "paywall"
      )
      created.subscriptions.create!(
        subscription_type: :pro,
        processor: :apple,
        processor_id: "prepared_#{SecureRandom.hex(8)}",
        amount: 9.99,
        currency: "usd",
        expiration_date: 1.year.from_now.to_date,
        status: :active
      )
      create_taken_naps!(created)
      created
    end

    Result.new(
      user: user,
      email: user.email,
      password: @password,
      daily_nap_count: @daily_nap_count,
      naps_taken: @naps_taken
    )
  rescue ActiveRecord::RecordInvalid => e
    raise Error, e.record.errors.full_messages.to_sentence
  end

  private

  def validate!
    unless @daily_nap_count.between?(0, MAX_DAILY_NAPS)
      raise Error, "Number of naps must be between 0 and #{MAX_DAILY_NAPS}"
    end

    unless @naps_taken.between?(0, MAX_NAPS_TAKEN)
      raise Error, "Number of naps already taken must be between 0 and #{MAX_NAPS_TAKEN}"
    end

    TZInfo::Timezone.get(@time_zone)
  rescue TZInfo::InvalidTimezoneIdentifier
    raise Error, "Time zone is not valid"
  end

  def integer_param(value, label)
    Integer(value)
  rescue ArgumentError, TypeError
    raise Error, "#{label} must be a whole number"
  end

  def generated_email
    "naps-#{@daily_nap_count}-taken-#{@naps_taken}-#{SecureRandom.hex(3)}@example.com"
  end

  def user_attributes
    {
      email: @email,
      password: @password,
      password_confirmation: @password,
      username: "parent_#{SecureRandom.hex(4)}",
      first_name: "Test",
      last_name: "Parent",
      baby_name: BABY_NAME,
      baby_birthdate: baby_birthdate,
      daily_nap_count: @daily_nap_count,
      time_zone: @time_zone,
      email_verified_at: Time.current
    }
  end

  def baby_birthdate
    Date.current - BIRTHDATE_MONTHS_AGO.fetch(@daily_nap_count).months
  end

  def create_taken_naps!(user)
    return if @naps_taken.zero?

    zone = Time.find_zone!(user.time_zone)
    now = Time.current.in_time_zone(zone)
    nap_schedule(now, user).each do |start_time, end_time|
      user.timer_runs.create!(
        start_time: start_time,
        end_time: end_time,
        duration: ((end_time - start_time) * 1000).round,
        submitted: true,
        active: false,
        paused: false,
        run_type: :sleeping,
        metadata: {}
      )
    end

    # Creating a run marks it active after the submitted callback. Clear that
    # so these naps count as finished, not as a nap in progress.
    user.timer_runs.update_all(active: false, paused: false, updated_at: Time.current)
  end

  def nap_schedule(now, user)
    day_begin = now.beginning_of_day
    latest_end = now - 1.minute
    daytime_start = day_begin + user.day_start_minutes.minutes
    daytime_end = day_begin + user.day_end_minutes.minutes
    window_end = [daytime_end, latest_end].min
    window_start = daytime_start

    if window_end <= window_start
      window_start = day_begin + 1.minute
      window_end = latest_end
    end

    if window_end <= window_start || window_end.to_date != window_start.to_date
      raise Error, not_enough_day_message
    end

    available = window_end - window_start
    preferred_total = (PREFERRED_NAP_LENGTH * @naps_taken) + (PREFERRED_GAP * (@naps_taken - 1))

    if available >= preferred_total
      nap_length = PREFERRED_NAP_LENGTH
      gap = PREFERRED_GAP
      window_start = window_end - preferred_total
    else
      gap = @naps_taken > 1 ? 1.minute : 0
      nap_length = (available - (gap * (@naps_taken - 1))) / @naps_taken
      raise Error, not_enough_day_message if nap_length < 1.minute
    end

    Array.new(@naps_taken) do |index|
      start_time = window_start + (index * (nap_length + gap))
      [start_time, start_time + nap_length]
    end
  end

  def not_enough_day_message
    "Not enough of today is left to record #{@naps_taken} #{'nap'.pluralize(@naps_taken)}. " \
      "Try a smaller number, or create the account later in the day."
  end
end
