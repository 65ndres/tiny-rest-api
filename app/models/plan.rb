class Plan < ApplicationRecord
  validates :name, presence: true
  validates :amount, numericality: { greater_than_or_equal_to: 0 }
  validates :interval, inclusion: { in: %w[month year] }

  def sync_with_stripe
    return unless stripe_price_id
    stripe_price = Stripe::Price.retrieve(stripe_price_id)
    self.amount = stripe_price.unit_amount / 100.0
    self.currency = stripe_price.currency
    self.interval = stripe_price.recurring.interval
    save!
  end

  def self.default_trial_plan
    find_or_create_by!(name: "Trial") do |plan|
      plan.amount = 0
      plan.currency = "usd"
      plan.interval = "month"
    end
  end
end
