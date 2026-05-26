# frozen_string_literal: true

class TimerRun < ApplicationRecord
  belongs_to :user, optional: true

  scope :submitted, -> { where(submitted: true) }

  validates :start_time, presence: true
  validates :end_time, :duration, presence: true, if: :submitted?
  validate :submitted_must_be_true_when_completed, if: -> { end_time.present? || duration.present? }

  private

  def submitted_must_be_true_when_completed
    return if submitted?

    errors.add(:submitted, 'must be true when end_time and duration are set')
  end
end
