class Subscription < ApplicationRecord
  belongs_to :user

  # Explicit attribute types for enums (required in Rails 7.2+ when schema may not be loaded)
  attribute :subscription_type, :integer
  attribute :processor, :integer

  enum subscription_type: {
    basic: 0,
    pro: 1,
  }

  enum processor: {
    stripe: 0,
    apple: 1,
    google: 2
  }

  enum status: {
    active: 0,
    expired: 1,
    cancelled: 2
  }

  scope :active_subscriptions, -> { where(status: :active) }
  scope :inactive_subscriptions, -> { where(status: [:expired, :cancelled]) }

  before_validation :sync_active_flag
  before_save :deactivate_other_subscriptions_for_user, if: :should_deactivate_siblings?

  private

  # Keep boolean `active` mirrored to status enum (avoid `active?` — conflicts with the column).
  def sync_active_flag
    write_attribute(:active, status_active_value?)
  end

  def status_active_value?
    status.to_s == "active"
  end

  def should_deactivate_siblings?
    status_active_value? && (new_record? || will_save_change_to_status?)
  end

  # Expire other active rows before save so the unique partial index cannot fail.
  def deactivate_other_subscriptions_for_user
    scope = user.subscriptions.active_subscriptions
    scope = scope.where.not(id: id) if id.present?
    scope.update_all(
      status: Subscription.statuses[:expired],
      active: false,
      updated_at: Time.current
    )
  end
end
