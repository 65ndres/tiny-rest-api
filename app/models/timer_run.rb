# frozen_string_literal: true

class TimerRun < ApplicationRecord
  belongs_to :user, optional: true

  scope :submitted, -> { where(submitted: true) }
  scope :active, -> { where(active: true) }

  validates :start_time, presence: true
  validates :end_time, :duration, presence: true, if: :submitted?
  validate :submitted_must_be_true_when_completed, if: -> { end_time.present? && duration.present? }
  validate :paused_only_when_not_submitted

  before_create :deactivate_previous_active_run
  before_save :clear_active_when_completed

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

    errors.add(:paused, 'cannot be true when submitted')
  end

  def submitted_must_be_true_when_completed
    return if submitted?

    errors.add(:submitted, 'must be true when end_time and duration are set')
  end
end
