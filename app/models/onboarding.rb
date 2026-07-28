class Onboarding < ApplicationRecord
  belongs_to :user

  # Stable string keys — append new steps as the funnel grows.
  # Order is defined by the client; this list is the allowlist for persistence.
  STEPS = %w[
    problem
    outcome
    baby_profile
    nap_count
    trust
    paywall
  ].freeze

  validates :last_completed_step,
            inclusion: { in: STEPS },
            allow_nil: true
end
