# frozen_string_literal: true

class Baby < ApplicationRecord
  DEFAULT_NAME = "Baby"
  MAX_NAME_LENGTH = 40

  belongs_to :user
  has_many :timer_runs, dependent: :destroy

  validates :name, length: { maximum: MAX_NAME_LENGTH }, allow_nil: true
  validates :daily_nap_count, inclusion: { in: 0..6 }
  validates :daily_nap_count_alt, inclusion: { in: 0..6 }, allow_nil: true
  validates :day_start_minutes, :day_end_minutes,
            presence: true,
            inclusion: { in: 0..1439 }
  validate :birthdate_must_be_valid, if: -> { birthdate.present? }
  validate :day_window_must_be_ordered
  validate :daily_nap_count_alt_must_be_allowed_range

  before_validation :normalize_name
  before_destroy :ensure_not_last_baby, unless: :destroyed_by_association

  scope :ordered, -> { order(:created_at, :id) }

  def display_name
    name.presence || DEFAULT_NAME
  end

  def time_zone
    user&.time_zone.presence || "UTC"
  end

  def as_api_json
    {
      id: id,
      name: name,
      birthdate: birthdate&.iso8601,
      daily_nap_count: daily_nap_count,
      daily_nap_count_alt: daily_nap_count_alt,
      day_start_minutes: day_start_minutes,
      day_end_minutes: day_end_minutes
    }
  end

  private

  def normalize_name
    self.name = name.strip.presence if name.is_a?(String)
  end

  def birthdate_must_be_valid
    if birthdate > Date.current
      errors.add(:birthdate, "must be in the past")
    elsif birthdate < 5.years.ago.to_date
      errors.add(:birthdate, "must be within the last 5 years")
    end
  end

  def day_window_must_be_ordered
    return if day_start_minutes.blank? || day_end_minutes.blank?
    return if day_start_minutes < day_end_minutes

    errors.add(:day_end_minutes, "must be after day start")
  end

  def daily_nap_count_alt_must_be_allowed_range
    return if daily_nap_count_alt.nil?

    unless User::ALLOWED_NAP_COUNT_RANGES.include?([ daily_nap_count, daily_nap_count_alt ])
      errors.add(:daily_nap_count_alt, "must be an allowed nap range")
    end
  end

  def ensure_not_last_baby
    return unless user && user.babies.where.not(id: id).none?

    errors.add(:base, "You need at least one baby profile")
    throw :abort
  end
end
