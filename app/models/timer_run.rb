# frozen_string_literal: true

class TimerRun < ApplicationRecord
  belongs_to :user, optional: true

  enum :run_type, {
    sleeping: "sleeping",
    nursing_left: "nursing_left",
    nursing_right: "nursing_right",
    bottle: "bottle"
  }, validate: true

  scope :submitted, -> { where(submitted: true) }
  scope :active, -> { where(active: true) }

  validates :start_time, presence: true
  validates :end_time, :duration, presence: true, if: :submitted?
  validate :submitted_must_be_true_when_completed, if: -> { end_time.present? && duration.present? }
  # Allow ~1 minute skew so "now" presses are not rejected.
  validate :start_time_must_not_be_in_the_future, if: -> { start_time.present? }
  # end_time must be after start_time for sleep/nursing; bottle feedings may use
  # end_time == start_time (duration 0 instant events).
  validate :end_time_must_be_after_start_time, if: -> { start_time.present? && end_time.present? }
  validate :paused_only_when_not_submitted
  validate :metadata_must_be_hash

  before_create :deactivate_previous_active_run, unless: :bottle_submitted_on_create?
  before_save :clear_active_when_completed

  def bottle_submitted_on_create?
    bottle? && submitted? && !persisted?
  end

  private

  def deactivate_previous_active_run
    return unless user

    user.transaction do
      previous = user.timer_runs.active.lock.first
      next unless previous

      attrs = { active: false }
      attrs[:end_time] = Time.current if previous.end_time.nil?
      previous.update!(attrs)
    end

    self.active = true
  end

  def clear_active_when_completed
    self.active = false if submitted?
  end

  def paused_only_when_not_submitted
    return unless paused? && submitted?

    errors.add(:paused, "cannot be true when submitted")
  end

  def submitted_must_be_true_when_completed
    return if submitted?

    errors.add(:submitted, "must be true when end_time and duration are set")
  end

  def start_time_must_not_be_in_the_future
    return if start_time <= Time.current + 1.minute

    errors.add(:start_time, "cannot be in the future")
  end

  def end_time_must_be_after_start_time
    return if bottle? && end_time == start_time
    return if end_time > start_time

    errors.add(:end_time, "must be after start time")
  end

  def metadata_must_be_hash
    return if metadata.is_a?(Hash)

    errors.add(:metadata, "must be a hash")
  end
end
